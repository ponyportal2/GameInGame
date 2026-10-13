import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
test('higher-priority personal gamesmith profile cannot shadow runtime profile',{timeout:15000},async t=>{
 const home=mkdtempSync(join(tmpdir(),'gs-copilot-shadow-'));mkdirSync(join(home,'agents'));
 const shadow=join(home,'agents','gamesmith.agent.md');
 writeFileSync(shadow,'---\nname: gamesmith\nmodel: shadow-model\n---\nSHADOW_PROFILE');
 let directory, previousId;
 for(const saved of [undefined,'copilot-fixture-session']){
  const f=fixture(t,{COPILOT_HOME:home},saved,directory);directory=f.directory;f.send({type:'prompt',id:'one',message:'hello'});
  assert((await f.until(r=>r.type==='complete')).ok);
  const selected=JSON.parse(readFileSync(join(f.directory,'native-workspace','.copilot-fixture-selected.json')));
  assert.match(selected.id,/^gamesmith-[0-9a-f-]{36}$/);
  assert.notEqual(selected.id,previousId);previousId=selected.id;
  assert.match(selected.profile,new RegExp('name: '+selected.id+'\\n'));
  assert.match(selected.profile,/Use only GameSmith tools/);assert.equal(selected.profile.includes('SHADOW_PROFILE'),false);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).model,'fixture-native-model');
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'copilot-fixture-session');
  const exited=new Promise(resolve=>f.child.once('close',resolve));f.child.stdin.end();await exited;
 }
 assert.match(readFileSync(shadow,'utf8'),/SHADOW_PROFILE/);
});
function fixture(t,extra={},saved,directory=mkdtempSync(join(tmpdir(),'gs-copilot-server-'))){
  mkdirSync(join(directory,'bridge'),{recursive:true});
  // Assemble exactly the files selected by the GDScript controller, rather than
  // testing source-tree relative imports that differ from the shipped runtime.
  const controller=readFileSync('src/agent/copilot_agent_controller.gd','utf8').split('func _native_modules()')[1].split('func _native_prompt()')[0];
  const inherited=readFileSync('src/agent/cline_agent_controller.gd','utf8').split('for pair in _native_modules() + ')[1].split(':')[0];
  const pairs=[...controller.matchAll(/\["([^"]+)", "([^"]+)"\]/g),...inherited.matchAll(/\["([^"]+)", "([^"]+)"\]/g)];
  assert.equal(pairs.length,8);
  for(const [,target,source] of pairs)copyFileSync(join('tools',source),join(directory,target));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:join(directory,'mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  if(saved){config.session=saved;writeFileSync(config.session_file,JSON.stringify({session:saved}));}
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{env:{...process.env,COPILOT_HOME:'',GAMESMITH_COPILOT_BIN:resolve('tools/testing/fake-copilot.mjs'),...extra},windowsHide:true});
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
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'copilot-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_COPILOT_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles its prompt before host retirement',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);

});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_COPILOT_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('private profile restricts executable tools without changing native model config',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const profile=readFileSync(join(f.directory,'native-workspace','.github/agents',JSON.parse(readFileSync(join(f.directory,'backend.json'))).agent+'.agent.md'),'utf8');
 assert.match(profile,/gamesmith-write/);assert.match(profile,/Use only GameSmith tools/);
 const argv=JSON.parse(readFileSync(join(f.directory,'native-workspace','.copilot-fixture-argv.json')));
 assert(argv.includes('--available-tools='+JSON.parse(profile.split('tools: ')[1].split('\n')[0]).map(t=>'mcp:'+t).join(',')));
 assert(argv.includes('--allow-tool=gamesmith'));assert(argv.includes('--disable-builtin-mcps'));
 assert.equal(argv.some(a=>/model|reasoning|compaction/.test(a)),false);
 const requests=readFileSync(join(f.directory,'native-workspace','.copilot-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(requests.some(r=>r.method==='session/set_model' || r.method==='authenticate'),false);
 assert.deepEqual(requests.find(r=>r.method==='session/set_config_option').params,{sessionId:'copilot-fixture-session',configId:'agent',value:JSON.parse(readFileSync(join(f.directory,'backend.json'))).agent});
 assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).model,'fixture-native-model');
 assert.equal((await f.until(r=>r.type==='context')).tokens,4321);
});

test('Other ACP cannot masquerade as Copilot through an executable override',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_COPILOT_WRONG_AGENT:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.match(result.error,/not GitHub Copilot/);
  const requests=readFileSync(join(f.directory,'native-workspace','.copilot-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(requests.some(r=>r.method==='authenticate' || r.method.startsWith('session/')),false);
});

test('resume cannot silently substitute another native conversation',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_COPILOT_DIFFERENT_SESSION:'1'},'copilot-fixture-session');
 f.send({type:'prompt',id:'one',message:'hello'});const r=await f.until(r=>r.type==='response');
 assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/different session/);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'copilot-fixture-session');
});

test('persistent turns keep profile instructions out of user history',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'first player message'});assert((await f.until(r=>r.type==='complete')).ok);
 f.send({type:'prompt',id:'two',message:'second player message'});await f.until(r=>r.id==='two');
 while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(r=>setTimeout(r,10));
 const profile=readFileSync(join(f.directory,'native-workspace','.github/agents',JSON.parse(readFileSync(join(f.directory,'backend.json'))).agent+'.agent.md'),'utf8');
 assert.match(profile,/Use only GameSmith tools/);
 const requests=readFileSync(join(f.directory,'native-workspace','.copilot-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.deepEqual(requests.filter(r=>r.method==='session/prompt').map(r=>r.params.prompt),[
   [{type:'text',text:'first player message'}],[{type:'text',text:'second player message'}]]);
});

test('agent selection is verified before accepting prompts',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_COPILOT_WRONG_MODE:'1'});f.send({type:'prompt',id:'one',message:'hello'});
 const r=await f.until(r=>r.type==='response');assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/restricted GameSmith/);
 assert.equal(existsSync(join(f.directory,'session.json')),false);
});
test('a stale native session preserves its reference and offers explicit reset',{timeout:15000},async t=>{
 const f=fixture(t,{},'missing-native-session');f.send({type:'prompt',id:'one',message:'hello'});
 const r=await f.until(r=>r.type==='response');assert.equal(r.success,false);assert.equal(r.initialization_failed,true);assert.match(r.error,/Start a new Copilot session/);
 assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'missing-native-session');
});

test('native credentials and custom configuration directory are inherited',{timeout:15000},async t=>{
 const home=mkdtempSync(join(tmpdir(),'gs-custom-copilot-home-'));
 const f=fixture(t,{COPILOT_HOME:home,GAMESMITH_COPILOT_EXPECT_HOME:home,COPILOT_GITHUB_TOKEN:'fixture-key',GAMESMITH_COPILOT_EXPECT_API_KEY:'fixture-key'});
 f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const requests=readFileSync(join(f.directory,'native-workspace','.copilot-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(requests.some(r=>r.method==='authenticate'),false);
});
