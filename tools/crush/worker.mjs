import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import {CrushServer} from './server.mjs';
import {CrushStream} from './protocol.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8')),emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
let session=config.session || '',saved=!!session,active,initializing,stopping=false,cancelling=false;
const stateFile=join(config.bridge_dir,'operation.json');
function state(enabled){writeFileSync(stateFile+'.tmp',JSON.stringify({active:enabled,session}));renameSync(stateFile+'.tmp',stateFile);}
state(false);
function saveSession(){if(saved)return;writeFileSync(config.session_file+'.tmp',JSON.stringify({session}));renameSync(config.session_file+'.tmp',config.session_file);saved=true;emit({type:'session',session});}
function fail(error){
  if(stopping)return;stopping=true;state(false);
  if(active){emit(active.accepted?{type:'complete',ok:false,text:active.stream?[...active.stream.texts.values()].join(''):'',error:error.message,runtime_failed:true}:{type:'response',id:active.request.id,success:false,error:error.message,initialization_failed:true});active.finish();active=undefined;}
  server.close();
}
const server=new CrushServer(config,{
  onStderr:line=>process.stderr.write(line+'\n'),onExit:fail,
  onEvent:event=>{
    const p=event.payload?.payload;
    if(!p)return;
    if(event.type==='permission_request'){
      // Exact native startup policy auto-allows only GameSmith MCP. Permission
      // titles and other native tool identities never grant authorization.
      void server.request(server.path('/permissions/grant'),'POST',{permission:p,action:'deny'}).catch(fail);return;
    }
    const operation=active;if(!operation?.accepted || !operation.stream)return;
    if(event.type==='message' && !operation.cancelled){
      for(const record of operation.stream.message(p)){saveSession();emit(record);}
    }
    if(event.type==='run_complete'){
      const result=operation.stream.complete(p);if(!result)return;
      if(!operation.cancelled){saveSession();for(const record of result.records)emit(record);emit({type:'complete',ok:result.ok,text:result.text,error:result.error});}
      if(active===operation){active=undefined;state(false);}operation.finish();
    }
  }
});
function ready(){return initializing ||= (async()=>{
  await server.start();
  if(session){
    try{const found=await server.request(server.path('/sessions/'+encodeURIComponent(session)));if(found.id!==session)throw new Error('Crush returned a different session.');}
    catch(error){throw new Error('Crush session could not be resumed: '+error.message+'. Start a new Crush session in Settings. The previous reference and chat are kept.');}
  }else session=(await server.request(server.path('/sessions'),'POST',{title:config.name || 'GameSmith'})).id;
  if(!session)throw new Error('Crush returned no session ID.');
  await server.request(server.path('/agent/init'),'POST',{interactive:true});
  // Agent readiness covers model setup, not asynchronous MCP discovery.
  // Updating too soon gives the first native turn no callable host tools.
  while(true){
    const states=await server.request(server.path('/mcp/states')),mcp=states.gamesmith;
    if(mcp?.state==='connected' && mcp.tool_count>0)break;
    if(mcp && !['starting','connected'].includes(mcp.state))throw new Error('Crush GameSmith MCP could not connect: '+(mcp.error || mcp.state));
    await new Promise(resolve=>setTimeout(resolve,50));
  }
  await server.request(server.path('/agent/update'),'POST');
  const agent=await server.request(server.path('/agent'));
  if(!agent.is_ready)throw new Error('Crush agent is not ready. Configure a model in Crush.');
  writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,version:server.version,model:agent.model_cfg?.model || agent.model?.id,provider:agent.model_cfg?.provider,reasoning_effort:agent.model_cfg?.reasoning_effort}));
})().catch(error=>{stopping=true;server.close();error.initializationFailed=true;throw error;});}
async function prompt(request,operation){
  try{
    await ready();if(operation.cancelled || active!==operation)return;
    const previous=await server.request(server.path('/sessions/'+encodeURIComponent(session)+'/messages'));
    operation.run=randomUUID();operation.stream=new CrushStream(session,operation.run,(previous || []).map(m=>m.id));
    operation.accepted=true;state(true);emit({type:'response',id:request.id,success:true});
    await server.request(server.path('/agent'),'POST',{session_id:session,run_id:operation.run,prompt:request.message});
    // Accepted native turns are durable even if Stop occurs before first text.
    if(active===operation)saveSession();
  }catch(error){
    if(active===operation){state(false);if(!operation.cancelled)emit(operation.accepted?{type:'complete',ok:false,text:'',error:error.message,initialization_failed:!!error.initializationFailed,runtime_failed:true}:{type:'response',id:request.id,success:false,error:error.message,initialization_failed:!!error.initializationFailed,runtime_failed:true});active=undefined;operation.finish();}
    stopping=true;server.close();
  }
}
async function cancel(request){
  if(cancelling){emit({type:'response',id:request.id,success:false,error:'Cancellation is already in progress.'});return;}
  cancelling=true;const operation=active;if(operation){operation.cancelled=true;state(false);}
  try{
    // Host Stop owns the five-second force fallback, including stuck startup.
    if(operation){await ready();if(operation.accepted){await server.request(server.path('/agent/sessions/'+encodeURIComponent(session)+'/cancel'),'POST');await operation.done;}}
    emit({type:'response',id:request.id,success:true});
  }catch(error){emit({type:'response',id:request.id,success:false,error:error.message});}finally{cancelling=false;}
}
createInterface({input:process.stdin}).on('line',line=>{
  let request;try{request=JSON.parse(line);}catch{return;}
  if(request.type==='cancel'){void cancel(request);return;}
  if(request.type!=='prompt' || active || cancelling || stopping){emit({type:'response',id:request.id,success:false,error:'Crush is busy or command is unsupported.'});return;}
  const operation={request,cancelled:false};operation.done=new Promise(resolve=>operation.finish=resolve);active=operation;void prompt(request,operation);
});
process.stdin.on('end',()=>{stopping=true;state(false);server.close();process.exit();});
