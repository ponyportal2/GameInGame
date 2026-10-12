import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline';
import { CodexServer } from './server.mjs';
import { threadParams, createEventNormalizer } from './protocol.mjs';
import { executeTool } from './tools.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
let session=config.session || '',contextTokens=config.context_tokens ?? null,active,initializing,cancelling=false,stopping=false;
function save() {
  if(!session)return;writeFileSync(config.session_file+'.tmp',JSON.stringify({session,context_tokens:contextTokens}));renameSync(config.session_file+'.tmp',config.session_file);
}
function events(method,params) {
  const operation=active;
  if(!operation || operation.cancelled) return;
  // Turn notifications can arrive before the turn/start response.
  if(!operation.normalize) {operation.events.push([method,params]);return;}
  for(const record of operation.normalize(method,params)) {
    if(record.type==='context') {contextTokens=record.tokens;save();}
    if(record.type==='complete') {active=undefined;operation.finish();}
    emit(record);
  }
}
const server=new CodexServer({workspace:config.workspace,onEvent:events,onStderr:line=>process.stderr.write(line+'\n'),
  onExit:error=>{if(stopping)return;const operation=active;
    if(operation && !operation.cancelled) emit(operation.accepted ? {type:'complete',ok:false,text:'',error:error.message} : {type:'response',id:operation.request.id,success:false,error:error.message});
    active=undefined;operation?.abort.abort();operation?.finish();
    stopping=true;process.stdout.write('',()=>process.exit(1));},
  onRequest:async(method,p)=>{
    if(method==='item/commandExecution/requestApproval' || method==='item/fileChange/requestApproval') return {decision:'decline'};
    if(method!=='item/tool/call') throw new Error('Unsupported Codex request: '+method);
    const operation=active;
    try {
      if(operation && !operation.turn && !operation.cancelled) {
        let aborted;
        const cancelled=new Promise(resolve=>{aborted=resolve;operation.abort.signal.addEventListener('abort',aborted,{once:true});});
        try {await Promise.race([operation.starting,cancelled]);}
        finally {operation.abort.signal.removeEventListener('abort',aborted);}
      }
      if(!operation || active!==operation || operation.cancelled || !operation.turn || p.threadId!==session || p.turnId!==operation.turn) throw new Error('GameSmith tool cancelled or does not belong to the active turn.');
      const result=await executeTool(config,p.tool,p.arguments,operation.abort.signal);
      return {success:result.ok!==false,contentItems:[{type:'inputText',text:JSON.stringify(result)}]};
    } catch(error) {return {success:false,contentItems:[{type:'inputText',text:error.message}]};}
  }});
function ready() {
  return initializing ||= (async()=>{
    await server.start();writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid}));
    const params=threadParams(config,readFileSync(config.prompt_path,'utf8'));
    // Keep the tool surface local to the game; never enable unrelated global
    // MCP tools alongside the bounded GameSmith dynamic tools.
    const nativeConfig=await server.request('config/read',{includeLayers:false});
    params.config.mcp_servers=Object.fromEntries(Object.keys(nativeConfig.config?.mcp_servers || {}).map(name=>[name,{enabled:false}]));
    let result;
    try {result=await server.request(session ? 'thread/resume' : 'thread/start',params);}
    catch(error) {
      if(session) error.message='Codex session could not be resumed: '+error.message+'. Retry, or open Settings → This game → Start new Codex session. The old session reference and chat will be kept.';
      throw error;
    }
    writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,model:result.model,reasoning_effort:result.reasoningEffort}));
    session=result.thread.id;save();emit({type:'session',session});
  })().catch(error=>{stopping=true;server.close();error.initializationFailed=true;throw error;});
}
async function prompt(request,operation) {
  try {
    await ready();if(operation.cancelled)return;
    const result=await server.request('turn/start',{threadId:session,input:[{type:'text',text:request.message}]});
    operation.turn=result.turn.id;
    if(operation.cancelled) {
      if(operation.events.some(([method,p])=>method==='turn/completed' && p.threadId===session && p.turn?.id===operation.turn)) operation.finish();
      return;
    }
    operation.normalize=createEventNormalizer(session,operation.turn);
    emit({type:'response',id:request.id,success:true});operation.accepted=true;
    for(const [method,params] of operation.events)events(method,params);operation.events=[];
  } catch(error) {
    if(active===operation && !operation.cancelled) {emit({type:'response',id:request.id,success:false,error:error.message,initialization_failed:!!error.initializationFailed});active=undefined;operation.finish();}
  } finally {
    // On readiness failure the backend is already closed. Keep the host pipe
    // readable until GameSmith receives the failure and retires this adapter.
    operation.started();
  }
}
async function cancel(request) {
  if(cancelling){emit({type:'response',id:request.id,success:false,error:'Cancellation is already in progress.'});return;}
  cancelling=true;const operation=active;if(operation){operation.cancelled=true;operation.abort.abort();}
  try {
    if(operation) {
      await operation.starting;
      if(operation.turn) await server.request('turn/interrupt',{threadId:session,turnId:operation.turn});
      // Interrupted notifications are ignored for UI completion but still settle
      // the native turn before a follow-up is permitted.
      if(operation.turn) await operation.done;
      if(active===operation)active=undefined;
    }
    emit({type:'response',id:request.id,success:true});
  } catch(error) {emit({type:'response',id:request.id,success:false,error:error.message});}
  finally {cancelling=false;}
}
const forward=server.onEvent;
server.onEvent=(method,p)=>{
  if(method==='turn/completed' && active?.cancelled && p.threadId===session) {
    if(p.turn?.id===active.turn)active.finish();else if(!active.turn)active.events.push([method,p]);
    return;
  }
  forward(method,p);
};
createInterface({input:process.stdin}).on('line',line=>{
  let request;try{request=JSON.parse(line);}catch{return;}
  if(request.type==='cancel'){void cancel(request);return;}
  if(request.type!=='prompt' || active || cancelling || stopping){emit({type:'response',id:request.id,success:false,error:'Codex is busy or command is unsupported.'});return;}
  const operation={request,events:[],abort:new AbortController()};
  operation.done=new Promise(resolve=>operation.finish=resolve);operation.starting=new Promise(resolve=>operation.started=resolve);
  active=operation;void prompt(request,operation);
});
process.stdin.on('end',()=>{stopping=true;active?.abort.abort();server.close();process.exit();});
