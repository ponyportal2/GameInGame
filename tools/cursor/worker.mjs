import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {createInterface} from 'node:readline';
import {CursorServer} from './server.mjs';
import {permissionResult,normalizeUpdate,PermissionCalls} from './protocol.mjs';
import {authorizeReload} from './approval.mjs';
const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let session=config.session || '',sessionSaved=!!session,active,initializing,cancelling=false,stopping=false;
const seenCalls=new Set();
function saveSession(){
  if(sessionSaved)return;
  writeFileSync(config.session_file+'.tmp',JSON.stringify({session}));renameSync(config.session_file+'.tmp',config.session_file);sessionSaved=true;
  emit({type:'session',session});
}
const server=new CursorServer(config,{
  onStderr:line=>process.stderr.write(line+'\n'),
  onEvent:(method,p)=>{
    if(method!=='session/update' || !active || !active.accepted || active.cancelled || p.sessionId!==session)return;
    active.calls.update(p.update);
    for(const r of normalizeUpdate(p.update)){saveSession();if(r.type==='delta' && r.kind==='assistant')active.text+=r.text;emit(r);}
  },
  onRequest:async(method,p)=>{
    if(method==='session/request_permission'){
      const operation=active,valid=!!operation?.accepted && !operation.cancelled && p.sessionId===session;
      const name=valid ? operation.calls.take(p.toolCall) : undefined;
      let permitted=!!name;
      if(name==='gamesmith__reload_game'){
        try{await authorizeReload(config,operation.abort.signal);}catch{permitted=false;}
      }
      return permissionResult(p,permitted && active===operation && !operation?.cancelled);
    }
    if(method==='cursor/ask_question')return {outcome:{outcome:'skipped',reason:'Continue with the player request and GameSmith tools.'}};
    if(method==='cursor/create_plan')return {outcome:{outcome:'rejected',reason:'Work directly through GameSmith tools.'}};
    throw new Error('GameSmith does not expose native Cursor filesystem or terminal access.');
  },
  onExit:error=>{
    if(stopping)return;stopping=true;
    if(active)emit(active.accepted ? {type:'complete',ok:false,text:active.text,error:error.message} : {type:'response',id:active.request.id,success:false,error:error.message,initialization_failed:true});
    active?.finish();active=undefined;server.close();process.stdout.write('',()=>process.exit(1));
  }
});
function ready(){return initializing ||= (async()=>{
  await server.start();
  const params=server.sessionParams();let result;
  try {result=await server.request(session ? 'session/load' : 'session/new',session ? {...params,sessionId:session} : params);}
  catch(error){if(session)error.message='Cursor session could not be resumed: '+error.message+'. Start a new Cursor session in Settings. The previous session reference and chat are kept.';throw error;}
  session=result.sessionId || session;
  if(!session)throw new Error('Cursor returned no session ID.');
  writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,model:result.models?.currentModelId}));
})().catch(error=>{stopping=true;server.close();error.initializationFailed=true;throw error;});}
async function prompt(request,operation){
  try {
    await ready();if(operation.cancelled)return;
    operation.accepted=true;emit({type:'response',id:request.id,success:true});
    operation.prompt=server.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:readFileSync(config.prompt_path,'utf8')+'\n\nPlayer request:\n'+request.message}]});
    const result=await operation.prompt;
    saveSession();
    if(!operation.cancelled)emit({type:'complete',ok:result.stopReason==='end_turn',text:operation.text,error:result.stopReason==='end_turn' ? '' : 'Cursor stopped: '+result.stopReason});
  }catch(error){
    // session/new allocates an ID before a native conversation exists. Do not
    // persist an unresumable reference if runtime setup fails before any event.
    if(!sessionSaved){stopping=true;server.close();error.initializationFailed=true;}
    if(active===operation && !operation.cancelled)emit(operation.accepted ? {type:'complete',ok:false,text:operation.text,error:error.message,initialization_failed:!!error.initializationFailed} : {type:'response',id:request.id,success:false,error:error.message,initialization_failed:!!error.initializationFailed});
  }
  finally{if(active===operation)active=undefined;operation.finish();}
}
async function cancel(request){
  if(cancelling){emit({type:'response',id:request.id,success:false,error:'Cancellation is already in progress.'});return;}
  cancelling=true;const operation=active;if(operation){operation.cancelled=true;operation.abort.abort();}
  try{
    // No model timeout: the host owns the five-second Stop fallback, including initialization.
    if(operation){await ready();if(operation.prompt)server.send({method:'session/cancel',params:{sessionId:session}});await operation.done;}
    emit({type:'response',id:request.id,success:true});
  }catch(error){emit({type:'response',id:request.id,success:false,error:error.message});}finally{cancelling=false;}
}
createInterface({input:process.stdin}).on('line',line=>{
  let r;try{r=JSON.parse(line);}catch{return;}
  if(r.type==='cancel'){void cancel(r);return;}
  if(r.type!=='prompt' || active || cancelling || stopping){emit({type:'response',id:r.id,success:false,error:'Cursor is busy or command is unsupported.'});return;}
  const operation={request:r,text:'',abort:new AbortController(),calls:new PermissionCalls(seenCalls)};operation.done=new Promise(resolve=>operation.finish=resolve);active=operation;void prompt(r,operation);
});
process.stdin.on('end',()=>{stopping=true;server.close();process.exit();});
