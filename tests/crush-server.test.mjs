import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={},saved){
  const directory=mkdtempSync(join(tmpdir(),'gs-crush-server-'));mkdirSync(join(directory,'bridge'));
  // Assemble exactly the files selected by the GDScript controller, rather than
  // testing source-tree relative imports that differ from the shipped runtime.
  const controller=readFileSync('src/agent/crush_agent_controller.gd','utf8').split('func _native_modules()')[1].split('func _native_prompt()')[0];
  const inherited=readFileSync('src/agent/cline_agent_controller.gd','utf8').split('for pair in _native_modules() + ')[1].split(':')[0];
  const pairs=[...controller.matchAll(/\["([^"]+)", "([^"]+)"\]/g),...inherited.matchAll(/\["([^"]+)", "([^"]+)"\]/g)];
  assert.equal(pairs.length,8);
  for(const [,target,source] of pairs)copyFileSync(join('tools',source),join(directory,target));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:join(directory,'mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  if(saved){config.session=saved;writeFileSync(config.session_file,JSON.stringify({session:saved}));}
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{env:{...process.env,CRUSH_HOME:'',GAMESMITH_CRUSH_BIN:resolve('tools/testing/fake-crush.mjs'),...extra},windowsHide:true});
  const records=[],waiters=[];let stderr='';child.stderr.on('data',d=>stderr+=d);
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);for(const w of [...waiters])if(w.predicate(r)){waiters.splice(waiters.indexOf(w),1);w.resolve(r);}});
  function until(predicate){const found=records.find(predicate);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Fixture timed out: '+stderr)),10000);waiters.push({predicate,resolve:r=>{clearTimeout(timer);resolve(r);}});});}
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  return {directory,child,records,until,send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}
test('persistent HTTP turns, canonical final text and native provider errors',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'policy'});assert((await f.until(r=>r.type==='complete')).ok);
  const pid=JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid;
  f.send({type:'prompt',id:'two',message:'partial-stream'});assert((await f.until(r=>r.id==='two')).success);
  const result=await f.until(r=>r.type==='complete' && r.text.includes('movement'));
  assert.equal(result.text,'I changed the player movement and fixed collisions.');
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,pid);
  f.send({type:'prompt',id:'three',message:'provider-error'});assert.match((await f.until(r=>r.type==='complete' && !r.ok)).error,/Fixture provider error/);
  assert.equal(f.records.some(r=>r.type==='context'),false);
});
for(const phase of ['agent/init','sessions/load'])test('readiness failure retires backend: '+phase,{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CRUSH_FAIL_METHOD:phase},phase==='sessions/load'?'missing-native-session':undefined);
  f.send({type:'prompt',id:'one',message:'hello'});const r=await f.until(r=>r.type==='response');
  assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/Fixture readiness failure/);
});
test('stale reference is preserved and reset is actionable',{timeout:15000},async t=>{
  const f=fixture(t,{},'missing-native-session');f.send({type:'prompt',id:'one',message:'hello'});
  const r=await f.until(r=>r.type==='response');assert.equal(r.success,false);assert.match(r.error,/Start a new Crush session/);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'missing-native-session');
});
test('native cancellation completes while general inference has no deadline',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.type==='delta');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);
  assert.equal(f.records.some(r=>r.type==='complete'),false);
});
test('private policy preserves native config and sends player messages only',{timeout:15000},async t=>{
  const f=fixture(t,{CRUSH_GLOBAL_CONFIG:'custom-home',GAMESMITH_CRUSH_EXPECT_CONFIG:'custom-home',OPENROUTER_API_KEY:'fixture-key',GAMESMITH_CRUSH_EXPECT_KEY:'fixture-key'});
  f.send({type:'prompt',id:'one',message:'first'});assert((await f.until(r=>r.type==='complete')).ok);
  f.send({type:'prompt',id:'two',message:'second'});await f.until(r=>r.id==='two');
  while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(resolve=>setTimeout(resolve,10));
  const requests=readFileSync(join(f.directory,'native-workspace','.crush-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(requests.filter(r=>r.path.endsWith('/agent') && r.method==='POST').map(r=>r.params.prompt),['first','second']);
  const policy=JSON.parse(readFileSync(join(f.directory,'native-data','crush.json')));
  assert.equal('models' in policy,false);assert.equal('providers' in policy,false);
  assert.equal(policy.options.context_paths.filter(p=>p===join(f.directory,'prompt.md')).length,1);
  assert.deepEqual(policy.mcp.gamesmith.args,[join(f.directory,'mcp.mjs'),join(f.directory,'runtime.json')]);
  assert.equal(policy.mcp.external.disabled,true);assert.equal(policy.options.disabled_tools.includes('agent'),true);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).model,'fixture-native-model');
});
for(const flag of ['GAMESMITH_CRUSH_WRONG_VERSION','GAMESMITH_CRUSH_WRONG_POLICY','GAMESMITH_CRUSH_MERGED_MCP_ARGS'])test('unknown native version/policy fails before inference: '+flag,{timeout:15000},async t=>{
  const f=fixture(t,{[flag]:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const r=await f.until(r=>r.type==='response');assert.equal(r.success,false);assert.equal(r.initialization_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});
test('HTTP prompt rejection does not save an allocated but unused session',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CRUSH_FAIL_METHOD:'agent/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const r=await f.until(r=>r.type==='complete');assert.equal(r.ok,false);assert.equal(r.initialization_failed,false);assert.equal(r.runtime_failed,true);assert.equal(existsSync(join(f.directory,'session.json')),false);
});
test('SSE loss fails and retires rather than leaving a busy turn indefinitely',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'lost-stream'});
  const r=await f.until(r=>r.type==='complete');assert.equal(r.ok,false);assert.match(r.error,/live event stream/);assert.equal(r.runtime_failed,true);assert.notEqual(r.initialization_failed,true);
});
test('agent update waits for native MCP initialization before first inference',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_CRUSH_DELAY_MCP:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const r=await f.until(r=>r.type==='complete' || r.type==='response' && !r.success);assert.equal(r.ok,true,r.error);
});
