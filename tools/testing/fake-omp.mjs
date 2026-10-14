import {createInterface} from 'node:readline';
import {appendFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,basename} from 'node:path';
const args=process.argv.slice(2),arg=n=>args[args.indexOf(n)+1];
const directory=arg('--session-dir');mkdirSync(directory,{recursive:true});
const resumed=args.includes('--resume'),file=resumed ? arg('--resume') : join(directory,'fixture-'+Date.now()+'.jsonl');
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
const policy=JSON.parse(process.env.GAMESMITH_OMP_POLICY);
let tools=[],turn,serial=0,replayIdentity;
const calls=new Map();
const response=(r,data={})=>emit({type:'response',id:r.id,success:true,data});
function trace(r){if(process.env.GAMESMITH_OMP_TRACE)appendFileSync(process.env.GAMESMITH_OMP_TRACE,JSON.stringify(r)+'\n');}
function settled(r){trace({type:'fixture_settled',promptId:r.id});emit({type:'session_settled'});}
function complete(r,text='Fixture complete',status='completed'){
  emit({type:'message_update',assistantMessageEvent:{type:'text_delta',delta:text.slice(0,5)}});
  emit({type:'message_end',messageId:'final-'+r.id,message:{role:'assistant',content:[{type:'text',text}],usage:{input:400,output:20,cacheRead:50}}});
  const delayed=r.message.includes('delayed-settlement');
  emit({type:'prompt_result',id:r.id,status,sessionSettled:!delayed});turn=undefined;
  if(delayed)setTimeout(()=>{
    emit({type:'message_update',assistantMessageEvent:{type:'text_delta',delta:' settled'}});
    emit({type:'message_end',messageId:'settled-'+r.id,message:{role:'assistant',content:[{type:'text',text:' settled'}]}});
    settled(r);
  },150);
  else setTimeout(()=>settled(r),r.message.includes('late-settlement') ? 80 : 0);
}
function call(name,arguments_={},identity){
  const id=identity?.id || 'host-'+ ++serial;
  return new Promise(resolve=>{calls.set(id,resolve);emit({type:'host_tool_call',id,toolCallId:identity?.toolCallId || 'tool-'+serial,toolName:name,arguments:arguments_});});
}
createInterface({input:process.stdin}).on('line',async line=>{
  const r=JSON.parse(line);
  trace(r);
  if(r.type==='host_tool_result'){calls.get(r.id)?.(JSON.parse(r.result.content[0].text));calls.delete(r.id);return;}
  if(r.type==='get_state'){
    if(process.env.GAMESMITH_OMP_STUCK_START)return;
    if(process.env.GAMESMITH_OMP_FAIL_METHOD==='initialize' || (resumed && process.env.GAMESMITH_OMP_FAIL_METHOD==='session/load')){emit({type:'response',id:r.id,success:false,error:'Fixture readiness failure'});return;}
    response(r,{sessionFile:file,sessionId:basename(file),model:{id:'fixture-free',provider:'fixture'},thinkingLevel:'high',contextUsage:{tokens:4321}});return;
  }
  if(r.type==='set_host_tools'){tools=r.tools;response(r,{toolNames:tools.map(t=>t.name)});return;}
  if(r.type==='abort_and_restore_queue'){
    if(process.env.GAMESMITH_OMP_STUCK_CANCEL)return;
    if(turn)complete(turn,'','aborted');response(r);return;
  }
  if(r.type==='prompt'){
    const localOnly=r.message==='Player request:\nlocal-only';
    response(r,{agentInvoked:r.message!=='/gamesmith-ready' && !localOnly});
    if(r.message==='/gamesmith-ready'){
      if(!process.env.GAMESMITH_OMP_NO_POLICY)writeFileSync(policy.path,JSON.stringify({nonce:process.env.GAMESMITH_OMP_BAD_POLICY ? 'stale' : policy.nonce,tools:tools.map(t=>t.name).sort()}));return;
    }
    writeFileSync(file,'native fixture history');turn=r;
    if(localOnly){turn=undefined;return;}
    if(r.message.includes('exit-backend')){process.exit(1);return;}
    if(r.message.includes('multiple-rounds')){
      emit({type:'message_update',messageId:'first-'+r.id,assistantMessageEvent:{type:'text_delta',delta:'Working. '}});
      emit({type:'message_end',messageId:'first-'+r.id,message:{role:'assistant',content:[{type:'text',text:'Working. '}]}});
    }
    if(r.message.includes('wait') || process.env.GAMESMITH_OMP_STUCK_TURN)return;
    if(r.message.includes('reload')){
      await call('gamesmith_write',{path:'main.gd',content:'extends Node\nvar acceptance_marker = 37\n'});
      await call('gamesmith_reload_game');
    }
    if(r.message.includes('test')){
      const run=await call('gamesmith_start_test_game',{mode:'headless'});
      await call('gamesmith_read_test_log',{run_id:run.run_id});await call('gamesmith_stop_test_game',{run_id:run.run_id});
    }
    if(r.message.includes('policy')){
      const native=await call('bash',{command:'echo forbidden'}),escape=await call('gamesmith_write',{path:'../escaped.txt',content:'forbidden'});
      if(native.ok!==false || escape.ok!==false){complete(r,'Policy failed','error');return;}
    }
    if(r.message.includes('replay-window')){
      const first={id:'host-'+(serial+1),toolCallId:'tool-'+(serial+1)};
      for(let n=0;n<2050;n++)await call('gamesmith_list',{path:'.'});
      replayIdentity={id:'host-'+serial,toolCallId:'tool-'+serial};
      const replay=await call('gamesmith_list',{path:'.'},first);
      complete(r,replay.ok===false ? 'Active replay denied after recent cache eviction' : 'Replay allowed','completed');return;
    }
    if(r.message.includes('recent-replay')){
      const replay=await call('gamesmith_list',{path:'.'},replayIdentity);
      complete(r,replay.ok===false ? 'Recent cross-turn replay denied' : 'Replay allowed','completed');return;
    }
    if(r.message.includes('provider-error')){emit({type:'prompt_result',id:r.id,status:'error',error:{message:'Fixture provider error'}});turn=undefined;setTimeout(()=>settled(r),0);return;}
    if(turn===r)complete(r);return;
  }
  emit({type:'response',id:r.id,success:false,error:'Unsupported fixture command'});
});
process.stdin.on('end',()=>process.exit());
