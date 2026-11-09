import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import {killProcessTree} from '../tools/agent/process-tree.mjs';

function fixture(t,env={},saved){
  const directory=mkdtempSync(join(tmpdir(),'gs-claude-worker-'));mkdirSync(join(directory,'bridge'));
  assembleHarnessRuntime('claude',directory);
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),prompt_path:join(directory,'prompt.md'),mcp:join(directory,'mcp.mjs'),config_path:join(directory,'runtime.json'),session:saved};
  writeFileSync(config.prompt_path,'Unique GameSmith system instructions');writeFileSync(config.config_path,JSON.stringify(config));
  if(saved)writeFileSync(config.session_file,JSON.stringify({session:saved}));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{windowsHide:true,env:{...process.env,GAMESMITH_CLAUDE_BIN:resolve('tools/testing/fake-claude.mjs'),...env}});
  const records=[];let stderr='';child.stderr.on('data',d=>stderr+=d);
  createInterface({input:child.stdout}).on('line',line=>records.push(JSON.parse(line)));
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  async function until(predicate){const end=Date.now()+10000;for(;;){const result=records.find(predicate);if(result)return result;if(Date.now()>end)throw new Error('Timeout: '+stderr+' '+JSON.stringify(records));await new Promise(r=>setTimeout(r,10));}}
  return {directory,child,records,until,send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}
test('persistent turns, exact requests, context and corrected final completion',{timeout:20000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'policy'});assert((await f.until(r=>r.type==='complete')).ok);
  const backend=JSON.parse(readFileSync(join(f.directory,'backend.json')));
  assert.equal(backend.model,'fixture-native-model');assert.equal((await f.until(r=>r.type==='context')).tokens,425);
  f.send({type:'prompt',id:'two',message:'corrected'});
  const result=await f.until(r=>r.type==='complete' && r.text==='Corrected completion');assert(result.corrected);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,backend.pid);
  const requests=readFileSync(join(f.directory,'native-workspace','.claude-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(requests.map(r=>r.message.content),['policy','corrected']);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'claude-fixture-session');
  assert(f.records.some(r=>r.kind==='thinking'));
});
test('explicit native resume preserves saved history',{timeout:15000},async t=>{
  const f=fixture(t,{},'claude-fixture-session');f.send({type:'prompt',id:'one',message:'follow up'});assert((await f.until(r=>r.type==='complete')).ok);
  const argv=JSON.parse(readFileSync(join(f.directory,'native-workspace','.claude-fixture-argv.json')));assert.equal(argv[argv.indexOf('--resume')+1],'claude-fixture-session');
});
test('first native tool runs after admission',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'write'});
  assert((await f.until(r=>r.type==='complete')).ok);
  assert.equal(readFileSync(join(f.directory,'admitted.txt'),'utf8'),'first native tool call');
});
for(const [name,env,saved] of [
  ['missing session',{},'missing-session'],['session substitution',{GAMESMITH_CLAUDE_DIFFERENT_SESSION:'1'},'claude-fixture-session'],
  ['unexpected builtin',{GAMESMITH_CLAUDE_EXTRA_TOOL:'1'},undefined],['first prompt failure',{GAMESMITH_CLAUDE_FAIL_METHOD:'session/prompt'},undefined],
])test(name+' rejects without replacing the reference',{timeout:15000},async t=>{
  const f=fixture(t,env,saved);f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert(result.initialization_failed);assert(result.runtime_failed);assert.equal(result.request_preserved,false);
  if(saved){assert.match(result.error,/Start a new Claude Code session/);assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,saved);}
  else assert.equal(existsSync(join(f.directory,'session.json')),false);
});
test('provider failure preserves an admitted conversation',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'provider-error'});const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert(result.request_preserved);assert.match(result.error,/Fixture provider error/);
});
test('Stop kills native process, disables MCP, and emits no stale completion',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'bridge','operation.json'))).active,false);
  assert.equal(f.records.some(r=>r.type==='complete'),false);
  f.send({type:'prompt',id:'late',message:'hello'});assert.equal((await f.until(r=>r.id==='late')).success,false);
});
