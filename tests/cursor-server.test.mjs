import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={}){
  const directory=mkdtempSync(join(tmpdir(),'gs-cursor-server-'));mkdirSync(join(directory,'bridge'));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:resolve('tools/cursor/mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,['tools/cursor/worker.mjs',config.config_path],{env:{...process.env,GAMESMITH_CURSOR_BIN:resolve('tools/testing/fake-cursor.mjs'),...extra},windowsHide:true});
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
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'cursor-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CURSOR_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles its prompt before host retirement',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);

});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CURSOR_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('logged-out CLI reports an actionable login failure without starting inference',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CURSOR_LOGGED_OUT:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.match(result.error,/cursor-agent login/);
});
test('native policy is private, native settings are untouched and ACP owns model selection',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
  const policy=JSON.parse(readFileSync(join(f.directory,'native-workspace','.cursor','cli.json')));
  assert.deepEqual(policy.permissions.deny.slice(0,3),['Shell(*)','Write(**)','Read(**)']);
  assert.equal(existsSync(join(f.directory,'.cursor','cli.json')),false);
  const requests=readFileSync(join(f.directory,'native-workspace','.cursor-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const start=requests.find(r=>r.method==='session/new');assert.equal(start.params.mcpServers[0].name,'gamesmith');
  assert.equal(start.params.cwd,join(f.directory,'native-workspace'));
  assert.equal(requests.some(r=>r.method==='session/set_model'),false);
});
