import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={},saved){
  const directory=mkdtempSync(join(tmpdir(),'gs-kiro-server-'));mkdirSync(join(directory,'bridge'));
  // Assemble exactly the files selected by the GDScript controller, rather than
  // testing source-tree relative imports that differ from the shipped runtime.
  const controller=readFileSync('src/agent/kiro_agent_controller.gd','utf8').split('func _native_modules()')[1].split('func _native_prompt()')[0];
  const inherited=readFileSync('src/agent/cline_agent_controller.gd','utf8').split('for pair in _native_modules() + ')[1].split(':')[0];
  const pairs=[...controller.matchAll(/\["([^"]+)", "([^"]+)"\]/g),...inherited.matchAll(/\["([^"]+)", "([^"]+)"\]/g)];
  assert.equal(pairs.length,8);
  for(const [,target,source] of pairs)copyFileSync(join('tools',source),join(directory,target));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:join(directory,'mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  if(saved){config.session=saved;writeFileSync(config.session_file,JSON.stringify({session:saved}));}
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{env:{...process.env,KIRO_HOME:'',GAMESMITH_KIRO_BIN:resolve('tools/testing/fake-kiro.mjs'),...extra},windowsHide:true});
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
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'kiro-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_KIRO_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles its prompt before host retirement',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);

});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_KIRO_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,false);assert.equal(result.runtime_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('private profile restricts executable tools without changing native model config',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const profile=JSON.parse(readFileSync(join(f.directory,'native-workspace','.kiro/agents/gamesmith.json'),'utf8'));
 assert(profile.tools.includes('@gamesmith/write'));assert.equal(profile.tools.some(t=>!t.startsWith('@gamesmith/')),false);assert.equal(profile.includeMcpJson,false);assert.deepEqual(profile.allowedTools,[]);assert.equal(profile.model,undefined);
 const argv=JSON.parse(readFileSync(join(f.directory,'native-workspace','.kiro-fixture-argv.json')));assert.deepEqual(argv,['acp','--agent-engine','v2','--agent','gamesmith']);
 const requests=readFileSync(join(f.directory,'native-workspace','.kiro-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(requests.some(r=>r.method==='session/set_model' || r.method==='authenticate'),false);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).model,'fixture-native-model');
 assert.equal((await f.until(r=>r.type==='context')).percent,12.5);
});

test('Other ACP cannot masquerade as Kiro through an executable override',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_KIRO_WRONG_AGENT:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.match(result.error,/not Kiro/);
  const requests=readFileSync(join(f.directory,'native-workspace','.kiro-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(requests.some(r=>r.method==='authenticate' || r.method.startsWith('session/')),false);
});

test('resume cannot silently substitute another native conversation',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_KIRO_DIFFERENT_SESSION:'1'},'kiro-fixture-session');
 f.send({type:'prompt',id:'one',message:'hello'});const r=await f.until(r=>r.type==='response');
 assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/different session/);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'kiro-fixture-session');
});

test('native load may omit ID but must receive the explicit session file', {timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_KIRO_LOAD_NO_ID:'1'},'kiro-fixture-session');f.send({type:'prompt',id:'one',message:'hello'});
 assert((await f.until(r=>r.type==='complete')).ok);
 const requests=readFileSync(join(f.directory,'native-workspace','.kiro-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 const load=requests.find(r=>r.method==='session/load');assert.equal(load.params.sessionId,'kiro-fixture-session');
 assert.match(load.params._meta['_kiro.dev/session_file'],/[\\/]\.kiro[\\/]sessions[\\/]cli[\\/]kiro-fixture-session\.json$/);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'kiro-fixture-session');
});
test('a native fallback to unrestricted default mode fails closed',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_KIRO_WRONG_MODE:'1'});f.send({type:'prompt',id:'one',message:'hello'});
 const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.match(result.error,/restricted GameSmith/);
});

test('custom KIRO_HOME controls explicit native resume path',{timeout:15000},async t=>{
 const home=mkdtempSync(join(tmpdir(),'gs-custom-kiro-home-'));
 const f=fixture(t,{KIRO_HOME:home},'kiro-fixture-session');
 f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const requests=readFileSync(join(f.directory,'native-workspace','.kiro-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(requests.find(r=>r.method==='session/load').params._meta['_kiro.dev/session_file'],join(home,'sessions','cli','kiro-fixture-session.json'));
});

test('persistent turns keep profile instructions out of user history',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'first player message'});assert((await f.until(r=>r.type==='complete')).ok);
 f.send({type:'prompt',id:'two',message:'second player message'});await f.until(r=>r.id==='two');
 while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(r=>setTimeout(r,10));
 const profile=JSON.parse(readFileSync(join(f.directory,'native-workspace','.kiro/agents/gamesmith.json'),'utf8'));
 assert.equal(profile.prompt,'Use only GameSmith tools.');
 const requests=readFileSync(join(f.directory,'native-workspace','.kiro-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.deepEqual(requests.filter(r=>r.method==='session/prompt').map(r=>r.params.prompt),[
   [{type:'text',text:'first player message'}],[{type:'text',text:'second player message'}]]);
});
