import {writeFile,readFile,rename,rm,appendFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
import {join} from 'node:path';
import {TOOL_NAMES} from '../command-code/policy.mjs';
const emit=value=>process.stdout.write(JSON.stringify(value)+'\n');
const mode=process.env.GAMESMITH_FAKE_ACP;
const nonce=process.env.GAMESMITH_POLICY_NONCE;
const pending = new Map();
const clientRequest=(id,method,params)=>new Promise(resolve=>{pending.set(id,resolve);emit({id,method,params});});
const ready=async phase=>writeFile(process.env.GAMESMITH_POLICY_READY,JSON.stringify({policy:'gamesmith',version:1,phase,nonce:mode==='wrong-nonce'?'stale':nonce,tools:phase==='session'?TOOL_NAMES:[]}));
const update=update=>emit({method:'session/update',params:{sessionId:'fixture-session',update}});
if(mode!=='missing-ready')await ready('loaded');
await writeFile('backend.json',JSON.stringify({pid:process.pid}));
createInterface({input:process.stdin}).on('line',async line=>{
 const r=JSON.parse(line),reply=result=>emit({id:r.id,result});
 if(!r.method){pending.get(r.id)?.(r);pending.delete(r.id);return;}
 if(r.method==='initialize'){reply({agentInfo:{name:'Command Code',version:'1.86.3'},agentCapabilities:{loadSession:true}});return;}
 if(r.method==='session/list'){reply({sessions:mode==='load-failed'?[]:[{sessionId:'fixture-session'}]});return;}
 if(['session/new','session/load'].includes(r.method)){
   if(mode==='load-failed'){emit({id:r.id,error:{message:'Native conversation not found'}});return;}
   reply({sessionId:'fixture-session'});
   update({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'OLD REPLAY'}});
   update({sessionUpdate:'available_commands_update',availableCommands:mode==='missing-session-ready'?[]:[{name:'gamesmith-ready-'+nonce}]});return;
 }
 if(r.method!=='session/prompt'){reply({});return;}
 const prompt=r.params.prompt[0].text;
 if(prompt==='provider-error'){emit({id:r.id,error:{code:-32000,message:'Fixture provider error'}});return;}
 if(prompt==='policy-error'){emit({type:'gamesmith_policy',nonce,event:{type:'mod_error',error:'Fixture policy validation failed'}});return;}
 if(prompt.startsWith('/gamesmith-ready-')){await ready('session');reply({stopReason:'end_turn'});return;}
 if(prompt==='/compact'){
   await appendFile('.compaction-fixture.jsonl',JSON.stringify({session:r.params.sessionId,pid:process.pid})+'\n');
   emit({type:'gamesmith_policy',nonce,event:{type:'compaction_start'}});
   const outcome=process.env.GAMESMITH_FAKE_COMPACTION || 'summarized';if(outcome==='slow')return;
   emit({type:'gamesmith_policy',nonce,event:{type:'compaction_outcome',outcome,tokensBefore:65020}});
   update({sessionUpdate:'usage_update',used:outcome==='summarized'?25000:65020});reply({stopReason:'end_turn'});return;
 }
 if(mode==='permissions'){
   const permission=await clientRequest('permission','session/request_permission',{sessionId:'fixture-session',toolCall:{title:'reload_game'},options:[{kind:'allow_once',optionId:'allow'},{kind:'reject_once',optionId:'deny'}]});
   const terminal=await clientRequest('terminal','terminal/create',{command:'must-not-run'});
   const filesystem=await clientRequest('fs','fs/write_text_file',{path:'must-not-exist',content:'denied'});
   await writeFile('permissions.json',JSON.stringify({permission,terminal,filesystem}));
 }
async function host(command,args={}) {
  update({sessionUpdate:'tool_call',title:command});
  const id = `fixture-${command}`;
  const path = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`request-${id}.json`);
  const response = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`response-${id}.json`);
  await writeFile(path+'.tmp',JSON.stringify({id,command,args}));
  await rename(path+'.tmp',path);
  for (;;) {
    try { const result = JSON.parse(await readFile(response,'utf8')); await rm(response);  return result; }
    catch(error) { if(error.code!=='ENOENT') throw error; }
    await new Promise(resolve=>setTimeout(resolve,25));
  }
}
if (prompt === 'repair-reload') {
  await writeFile('main.gd','extends Node\nfunc broken(:\n');
  const failed = await host('reload_game');
  if (failed.ok || !failed.error || !failed.diagnostics) throw new Error('Missing actionable reload failure');
  await writeFile('main.gd','extends Node\nvar repaired = true\n');
  const tested = await host('start_test_game',{mode:'headless'});
  if (!tested.ok) throw new Error(tested.error);
  await host('read_test_log',{run_id:tested.run_id});
  await host('stop_test_game',{run_id:tested.run_id});
  const loaded = await host('reload_game');
  if (!loaded.ok) throw new Error(loaded.error);
}
if (prompt === 'reload') {
  await writeFile('main.gd','extends Node\n');
  const result = await host('reload_game');
  if (!result.ok) throw new Error(result.error);
}
if (prompt === 'test') {
  await writeFile('main.gd','extends Node\n');
  const started = await host('start_test_game',{mode:'headless'});
  if (!started.ok) throw new Error(started.error);
  const stopped = await host('stop_test_game',{run_id:started.run_id});
  if (stopped.state !== 'exited') throw new Error('Stop bridge did not wait for confirmed exit');
}

update({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'Fixture finished'}});
update({sessionUpdate:'usage_update',used:prompt==='large-context'?65020:5120});
reply({stopReason:'end_turn'});
});
process.stdin.on('end',()=>process.exit());
