import {atomicSaveSession,failureRecord} from './session-state.mjs';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {createInterface} from 'node:readline';
import {CopilotServer} from './server.mjs';
import {permissionResult,normalizeUpdate} from './protocol.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let contextTokens=config.context_tokens;
let session=config.session || '',sessionSaved=!!session,active,initializing,cancelling=false,stopping=false;

const stateFile=join(config.bridge_dir,'operation.json');
function state(enabled){writeFileSync(stateFile+'.tmp',JSON.stringify({active:enabled,session}));renameSync(stateFile+'.tmp',stateFile);}
state(false);
function saveSession(){
  if(sessionSaved)return;
  atomicSaveSession(config.session_file,{session,context_tokens:contextTokens});sessionSaved=true;
  emit({type:'session',session});
}
const server=new CopilotServer(config,{
  onStderr:line=>process.stderr.write(line+'\n'),
  onEvent:(method,p)=>{
    if(method!=='session/update' || p.sessionId!==session)return;
    if(p.update?.sessionUpdate==='config_option_update'){
      const model=p.update.configOptions?.find(o=>o.id==='model')?.currentValue;
      if(model)writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,agent:server.agentId,model}));
    }
    // usage_update is a current-context measurement and can arrive after the
    // final prompt response. Per-turn result.usage.totalTokens is not context.
    if(p.update?.sessionUpdate==='usage_update' && sessionSaved){
      for(const r of normalizeUpdate(p.update)){contextTokens=r.tokens;atomicSaveSession(config.session_file,{session,context_tokens:contextTokens});emit(r);}return;
    }
    if(!active?.accepted || active.cancelled)return;
    for(const r of normalizeUpdate(p.update)){saveSession();if(r.type==='delta' && r.kind==='assistant')active.text+=r.text;emit(r);}
  },
  onRequest:async(method,p)=>{
    if(method==='session/request_permission'){
      // Native permission requests never authorize tools. Copilot's exact
      // startup/profile allowlists expose GameSmith MCP only; the MCP bridge
      // independently checks active operation, workspace and reload approval.
      return permissionResult(p);
    }
    throw new Error('GameSmith does not expose native Copilot filesystem or terminal access.');
  },
  onExit:error=>{
    if(stopping)return;stopping=true;
    state(false);if(active)emit(active.accepted ? {type:'complete',ok:false,text:active.text,error:error.message} : {type:'response',id:active.request.id,success:false,error:error.message,initialization_failed:true});
    active?.finish();active=undefined;server.close();process.stdout.write('',()=>process.exit(1));
  }
});
function ready(){return initializing ||= (async()=>{
  await server.start();
  const params=server.sessionParams();let result;
  try {result=await server.request(session ? 'session/load' : 'session/new',session ? {...params,sessionId:session} : params);}
  catch(error){if(session)error.message='Copilot session could not be resumed: '+error.message+'. Start a new Copilot session in Settings. The previous session reference and chat are kept.';throw error;}
  if(session && result.sessionId && result.sessionId!==session)throw new Error('Copilot resumed a different session. Start a new Copilot session in Settings; the previous reference is kept.');
  session=result.sessionId || session;
  if(!session)throw new Error('Copilot returned no session ID.');
  // --agent is ignored by the tested ACP mode: explicitly select and verify.
  const selected=await server.request('session/set_config_option',{sessionId:session,configId:'agent',value:server.agentId});
  if(selected.configOptions?.find(o=>o.id==='agent')?.currentValue!==server.agentId)throw new Error('Copilot did not load the restricted GameSmith agent profile. Update Copilot CLI.');
  server.cleanupProfiles();
  writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,agent:server.agentId,model:selected.configOptions?.find(o=>o.id==='model')?.currentValue || result.configOptions?.find(o=>o.id==='model')?.currentValue || result.models?.currentModelId}));
})().catch(error=>{stopping=true;server.close();error.initializationFailed=true;throw error;});}
async function prompt(request,operation){
  try {
    await ready();if(operation.cancelled)return;
    operation.accepted=true;state(true);emit({type:'response',id:request.id,success:true});
    operation.prompt=server.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:request.message}]});
    const result=await operation.prompt;
    saveSession();
    if(!operation.cancelled)emit({type:'complete',ok:result.stopReason==='end_turn',text:operation.text,error:result.stopReason==='end_turn' ? '' : 'Copilot stopped: '+result.stopReason});
  }catch(error){
    // session/new allocates an ID before a native conversation exists. Do not
    // persist an unresumable reference if runtime setup fails before any event.
    if(!sessionSaved){stopping=true;server.close();error.runtimeFailed=true;}
    if(active===operation && !operation.cancelled)emit(failureRecord(operation,error));
  }
  finally{if(active===operation){active=undefined;state(false);}operation.finish();}
}
async function cancel(request){
  if(cancelling){emit({type:'response',id:request.id,success:false,error:'Cancellation is already in progress.'});return;}
  cancelling=true;const operation=active;if(operation){operation.cancelled=true;state(false);operation.abort.abort();}
  try{
    // No model timeout: the host owns the five-second Stop fallback, including initialization.
    if(operation){await ready();if(operation.prompt)server.send({method:'session/cancel',params:{sessionId:session}});await operation.done;}
    emit({type:'response',id:request.id,success:true});
  }catch(error){emit({type:'response',id:request.id,success:false,error:error.message});}finally{cancelling=false;}
}
createInterface({input:process.stdin}).on('line',line=>{
  let r;try{r=JSON.parse(line);}catch{return;}
  if(r.type==='cancel'){void cancel(r);return;}
  if(r.type!=='prompt' || active || cancelling || stopping){emit({type:'response',id:r.id,success:false,error:'Copilot is busy or command is unsupported.'});return;}
  const operation={request:r,text:'',abort:new AbortController()};operation.done=new Promise(resolve=>operation.finish=resolve);active=operation;void prompt(r,operation);
});
process.stdin.on('end',()=>{stopping=true;state(false);server.close();process.exit();});
