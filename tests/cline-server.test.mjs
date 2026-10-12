import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={}){
  const directory=mkdtempSync(join(tmpdir(),'gs-cline-server-'));mkdirSync(join(directory,'bridge'));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:resolve('tools/cline/mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,['tools/cline/worker.mjs',config.config_path],{env:{...process.env,GAMESMITH_CLINE_BIN:resolve('tools/testing/fake-cline.mjs'),...extra},windowsHide:true});
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
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'cline-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CLINE_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles prompt and allows another message',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);
  f.send({type:'prompt',id:'two',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CLINE_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('native catalog fallback is replaced before the first prompt',{timeout:15000},async t=>{
  const f=fixture(t,{CLINE_MODEL:'native-free-model',GAMESMITH_CLINE_CATALOG_MODEL:'catalog-fallback'});
  f.send({type:'prompt',id:'one',message:'hello'});
  assert((await f.until(r=>r.type==='complete')).ok);
  const requests=readFileSync(join(f.directory,'.cline-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const selection=requests.findIndex(r=>r.method==='session/set_model');
  assert(selection>=0 && selection<requests.findIndex(r=>r.method==='session/prompt'));
  assert.equal(requests[selection].params.modelId,'native-free-model');
});

test('ACP inherits a native API-key provider without persisting its key',{timeout:15000},async t=>{
  const data=mkdtempSync(join(tmpdir(),'gs-cline-provider-')),path=join(data,'providers.json'),key='fixture-private-api-key';
  writeFileSync(path,JSON.stringify({lastUsedProvider:'openrouter',providers:{openrouter:{settings:{model:'native-model',auth:{apiKey:key}}}}}));
  const f=fixture(t,{CLINE_PROVIDER_SETTINGS_PATH:path,CLINE_API_KEY:'',GAMESMITH_CLINE_EXPECT_API_KEY:key});
  f.send({type:'prompt',id:'one',message:'hello'});
  assert((await f.until(r=>r.type==='complete' || r.type==='response' && !r.success)).ok);
  for(const name of ['runtime.json','backend.json','session.json'])assert(!readFileSync(join(f.directory,name),'utf8').includes(key));
});
