import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={},saved){
  const directory=mkdtempSync(join(tmpdir(),'gs-codebuddy-server-'));mkdirSync(join(directory,'bridge'));
  assembleHarnessRuntime('codebuddy',directory);
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:join(directory,'mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  if(saved){config.session=saved;writeFileSync(config.session_file,JSON.stringify({session:saved}));}
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{env:{...process.env,GAMESMITH_CODEBUDDY_BIN:resolve('tools/testing/fake-codebuddy.mjs'),...extra},windowsHide:true});
  const records=[],waiters=[];let stderr='';child.stderr.on('data',d=>stderr+=d);
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);for(const w of [...waiters])if(w.predicate(r)){waiters.splice(waiters.indexOf(w),1);w.resolve(r);}});
  function until(predicate){const found=records.find(predicate);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Fixture timed out: '+stderr)),10000);waiters.push({predicate,resolve:r=>{clearTimeout(timer);resolve(r);}});});}
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  return {directory,child,records,until,send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}
test('persistent ACP turns, native policy and provider failure',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'policy'});
  assert((await f.until(r=>r.type==='complete')).ok);
  const pid=JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid;
  f.send({type:'prompt',id:'two',message:'follow up'});assert((await f.until(r=>r.id==='two')).success);
  while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(r=>setTimeout(r,10));
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,pid);
  f.send({type:'prompt',id:'three',message:'provider-error'});const result=await f.until(r=>r.type==='complete' && !r.ok);assert.match(result.error,/Fixture provider error/);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'codebuddy-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CODEBUDDY_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles its prompt before host retirement',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);

});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CODEBUDDY_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,false);assert.equal(result.runtime_failed,true);assert.equal(result.request_preserved,false);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('native launch restricts tools without changing native model configuration',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const argv=JSON.parse(readFileSync(join(f.directory,'native-workspace','.codebuddy-fixture-argv.json')));
 assert.match(argv[argv.indexOf('--tools')+1],/^NoDefer\(mcp__gamesmith__/);assert(argv.includes('--strict-mcp-config'));
 const requests=readFileSync(join(f.directory,'native-workspace','.codebuddy-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(requests.some(r=>r.method==='session/set_model' || r.method==='authenticate'),false);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).model,'fixture-native-model');
 assert.equal((await f.until(r=>r.type==='context')).tokens,425);
});

test('each ACP user turn contains only its request, including recovery on resume',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 f.send({type:'prompt',id:'two',message:'follow up'});
 await f.until(r=>r.id==='two');
 while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(r=>setTimeout(r,10));
 const prompts=readFileSync(join(f.directory,'native-workspace','.codebuddy-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse).filter(r=>r.method==='session/prompt');
 assert.deepEqual(prompts.map(r=>r.params.prompt),['hello','follow up'].map(text=>[{type:'text',text}]));
 const resumed=fixture(t,{},'codebuddy-fixture-session');
 const recovery='Recover the unfinished request.\nKeep existing changes.';
 resumed.send({type:'prompt',id:'recovery',message:recovery});assert((await resumed.until(r=>r.type==='complete')).ok);
 const requests=readFileSync(join(resumed.directory,'native-workspace','.codebuddy-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert(requests.some(r=>r.method==='session/load'));
 assert.deepEqual(requests.find(r=>r.method==='session/prompt').params.prompt,[{type:'text',text:recovery}]);
});

test('resume cannot silently substitute another native conversation',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_CODEBUDDY_DIFFERENT_SESSION:'1'},'codebuddy-fixture-session');
 f.send({type:'prompt',id:'one',message:'hello'});const r=await f.until(r=>r.type==='response');
 assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/different session/);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'codebuddy-fixture-session');
});
