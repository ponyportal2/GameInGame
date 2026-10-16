import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,readdirSync,renameSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
function fixture(t,extra={}){
  const directory=mkdtempSync(join(tmpdir(),'gs-grok-build-server-'));mkdirSync(join(directory,'bridge'));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),mcp:resolve('tools/grok-build/mcp.mjs'),prompt_path:join(directory,'prompt.md'),config_path:join(directory,'runtime.json')};
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(config.config_path,JSON.stringify(config));
  const child=spawn(process.execPath,['tools/grok-build/worker.mjs',config.config_path],{env:{...process.env,GAMESMITH_GROK_BUILD_BIN:resolve('tools/testing/fake-grok-build.mjs'),...extra},windowsHide:true});
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
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'grok-build-fixture-session');
});
test('readiness failure is reported for host retirement',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_GROK_BUILD_FAIL_METHOD:'session/new'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
});
test('native Stop settles its prompt before host retirement',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'wait'});await f.until(r=>r.id==='one');
  f.send({type:'cancel',id:'stop'});assert((await f.until(r=>r.id==='stop')).success);

});
test('first-prompt initialization failure does not save an unresumable ID',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_GROK_BUILD_FAIL_METHOD:'session/prompt'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.initialization_failed,false);assert.equal(result.runtime_failed,true);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('Grok policy removes native tools and leaves native model settings alone',{timeout:15000},async t=>{
 const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
 const requests=readFileSync(join(f.directory,'native-workspace','.grok-build-fixture-requests.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
 const start=requests.find(r=>r.method==='session/new');assert.equal(start.params.mcpServers[0].name,'gamesmith');assert.deepEqual(start.params._meta,{yoloMode:false,autoMode:false});
 assert.equal(requests.some(r=>['session/set_model','session/set_config_option'].includes(r.method)),false);
 const args=JSON.parse(readFileSync(join(f.directory,'native-workspace','.grok-build-fixture-argv.json')));assert.deepEqual(args,['--tools','use_tool,search_tool','--no-subagents','--disable-web-search','--permission-mode','default','agent','--no-leader','stdio']);
 assert.match(readFileSync(join(f.directory,'native-workspace','.grok/config.toml'),'utf8'),/ask = \["MCPTool\(\*\)"\]/);
});
test('Cursor ACP cannot masquerade as Grok Build',{timeout:15000},async t=>{
 const f=fixture(t,{GAMESMITH_GROK_BUILD_WRONG_AGENT:'1'});f.send({type:'prompt',id:'one',message:'hello'});
 const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.match(result.error,/not Grok Build/);
});

test('Blender waits before MCP execution and passes its single-use approval',{timeout:15000+Number(process.env.GAMESMITH_TEST_BLENDER_WAIT_MS || 0)},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'blender',message:'blender-approval'});
  const bridge=join(f.directory,'bridge');
  const request=async()=>{
    for(let i=0;i<800;i++){
      const file=readdirSync(bridge).find(n=>/^request-.*\.json$/.test(n));
      if(file){
        const path=join(bridge,file),claimed=path+'.claimed';
        try{renameSync(path,claimed);}catch(error){if(['EPERM','EACCES','ENOENT'].includes(error.code)){await new Promise(r=>setTimeout(r,10));continue;}throw error;}
        const data=JSON.parse(readFileSync(claimed,'utf8'));rmSync(claimed);return data;
      }
      await new Promise(r=>setTimeout(r,10));
    }
    throw new Error('No Blender approval request');
  };
  const auth=await request();assert.equal(auth.command,'authorize_blender');
  assert.deepEqual(auth.args.blender_args,{action:'start',script:'build.py'});
  // Only ACP permission is pending. No MCP host call can race the player.
  await new Promise(r=>setTimeout(r,Number(process.env.GAMESMITH_TEST_BLENDER_WAIT_MS || 100)));
  assert.equal(readdirSync(bridge).filter(n=>n.startsWith('request-')).length,0);
  writeFileSync(join(bridge,'response-'+auth.id+'.json'),JSON.stringify({ok:true,run_id:'approved',state:'running'}));
  const call=await request();assert.equal(call.command,'blender');
  assert.deepEqual(call.args,{action:'start',script:'build.py',approval_token:auth.args.token});
  writeFileSync(join(bridge,'response-'+call.id+'.json'),JSON.stringify({ok:true,run_id:'approved',state:'running'}));
  assert((await f.until(r=>r.type==='complete')).ok);
  assert.equal(existsSync(join(bridge,'blender-grant.json')),false);
});
