import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={},session='') {
  const directory=mkdtempSync(join(tmpdir(),'gs-agy-server-'));mkdirSync(join(directory,'bridge'));
  assembleHarnessRuntime('agy',directory);
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session,session_file:join(directory,'session.json'),mcp:join(directory,'mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  // Runtime layout is the same as a host-prepared integration.
  config.mcp=join(directory,'mcp.mjs');writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),config.config_path],{env:{...process.env,GAMESMITH_AGY_BIN:resolve('tools/testing/fake-agy.mjs'),...extra},windowsHide:true});
  const records=[],waiters=[];let stderr='';child.stderr.on('data',d=>stderr+=d);
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);for(const w of [...waiters])if(w.predicate(r)){waiters.splice(waiters.indexOf(w),1);w.resolve(r);}});
  function until(predicate){const found=records.find(predicate);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Fixture timed out: '+stderr)),10000);waiters.push({predicate,resolve:r=>{clearTimeout(timer);resolve(r);}});});}
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  return {directory,child,records,until,send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}
test('persistent native stream turns, canonical final answer, native model settings and provider failure',{timeout:20000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'policy'});assert((await f.until(r=>r.type==='complete')).ok);
  const pid=JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid;
  assert.equal(f.records.filter(r=>r.type==='delta').map(r=>r.text).join(''),'Fixture finished');
  assert.equal(f.records.some(r=>r.type==='context'),false);
  f.send({type:'prompt',id:'two',message:'follow up'});assert((await f.until(r=>r.id==='two')).success);
  await f.until(r=>r.type==='complete' && f.records.filter(r=>r.type==='complete').length===2);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,pid);
  const args=JSON.parse(readFileSync(join(f.directory,'native-workspace','.agy-fixture-argv.json')));
  assert.deepEqual(args,['--agent','gamesmith','--disable-slash-commands','--input-format','stream-json','--output-format','stream-json']);
  f.send({type:'prompt',id:'three',message:'provider-error'});
  const result=await f.until(r=>r.type==='complete' && !r.ok);assert.match(result.error,/Fixture provider error/);assert(result.runtime_failed);assert.notEqual(result.initialization_failed,true);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'agy-fixture-session');
});
test('explicit resume is passed and mismatched identity cannot overwrite reference',{timeout:15000},async t=>{
  const f=fixture(t,{},'agy-fixture-session');f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
  const args=JSON.parse(readFileSync(join(f.directory,'native-workspace','.agy-fixture-argv.json')));assert.deepEqual(args.slice(-2),['--conversation','agy-fixture-session']);
  const bad=fixture(t,{GAMESMITH_AGY_WRONG_SESSION:'1'},'agy-fixture-session');writeFileSync(join(bad.directory,'session.json'),JSON.stringify({session:'agy-fixture-session'}));
  bad.send({type:'prompt',id:'one',message:'hello'});const result=await bad.until(r=>r.type==='complete');assert.match(result.error,/Start a new AGY session/);
  assert.equal(JSON.parse(readFileSync(join(bad.directory,'session.json'))).session,'agy-fixture-session');
});
test('Stop kills a backend stuck before native init',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_AGY_STUCK_START:'1'});f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'bridge','operation.json'))).active,false);
});
test('missing native executable fails acceptance and requests a clean host retry',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_AGY_BIN:join(tmpdir(),'gamesmith-no-such-agy.exe')});
  f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert(result.initialization_failed);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});
test('native hook and MCP guard fail closed with unavailable or idle operation state',{timeout:15000},async t=>{
  const directory=mkdtempSync(join(tmpdir(),'gs-agy-policy-')),bridge=join(directory,'bridge');mkdirSync(bridge);
  const config={workspace:directory,bridge_dir:bridge},file=join(directory,'runtime.json');writeFileSync(file,JSON.stringify(config));
  async function hook(payload){
    const child=spawn(process.execPath,['tools/agy/hook.mjs',file],{windowsHide:true});let output='';child.stdout.on('data',d=>output+=d);
    child.stdin.end(JSON.stringify(payload));await new Promise(resolve=>child.on('exit',resolve));return JSON.parse(output);
  }
  const call={conversationId:'session',toolCall:{name:'call_mcp_tool',args:{ServerName:'gamesmith',ToolName:'write',Arguments:{path:'main.gd',content:'ok'}}}};
  assert.equal((await hook(call)).decision,'deny');
  writeFileSync(join(bridge,'operation.json'),JSON.stringify({active:true,session:'session'}));assert.equal((await hook(call)).decision,'auto_approve');
  writeFileSync(join(bridge,'operation.json'),JSON.stringify({active:false,session:'session'}));assert.equal((await hook(call)).decision,'deny');
  const child=spawn(process.execPath,['tools/agy/mcp.mjs',file],{windowsHide:true});t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  const reply=new Promise(resolve=>createInterface({input:child.stdout}).once('line',line=>resolve(JSON.parse(line))));
  child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'write',arguments:{path:'idle.txt',content:'bad'}}})+'\n');
  assert.equal((await reply).result.isError,true);assert.equal(existsSync(join(directory,'idle.txt')),false);
});
