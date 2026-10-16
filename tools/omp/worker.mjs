import {readFileSync,writeFileSync,renameSync,existsSync} from 'node:fs';
import {basename,dirname,join} from 'node:path';
import {createInterface} from 'node:readline';
import {OmpServer} from './server.mjs';
const {toolContent}=await import(existsSync(new URL('./host-tools.mjs',import.meta.url)) ? './host-tools.mjs' : '../opencode/host-tools.mjs');
const {toolSpecs,executeTool}=await import(existsSync(new URL('./workspace-tools.mjs',import.meta.url)) ? './workspace-tools.mjs' : '../codex/tools.mjs');
const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const specs=toolSpecs(),allowed=new Set(specs.map(t=>t.name));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let session=config.session || '',initializing,active,stopping=false,cancelling=false;
const seenCalls=new Set();
function saveSession(){
  session=basename(server.state.sessionFile);
  writeFileSync(config.session_file+'.tmp',JSON.stringify({session}));renameSync(config.session_file+'.tmp',config.session_file);
  emit({type:'session',session});
}
const server=new OmpServer(config,{
  onStderr:line=>process.stderr.write(line+'\n'),
  onExit:error=>{
    if(stopping)return;
    stopping=true;
    if(active){active.abort.abort();emit(active.dispatched ? {type:'complete',ok:false,text:active.text,error:error.message,runtime_failed:true} : {type:'response',id:active.request.id,success:false,error:error.message,initialization_failed:true});active.resolve?.({status:'aborted'});active.settle();active.finish();active=undefined;}
    server.close();
    // Retire the adapter even if no player turn was active. Otherwise the host
    // sees a live worker and keeps sending requests to a dead native backend.
    process.stdout.write('',()=>process.exit(1));
  },
  onEvent:r=>{
    const op=active;if(!op?.dispatched || op.cancelled)return;
    if(r.type==='host_tool_call')void hostCall(r,op);
    if(r.type==='host_tool_cancel')op.calls.get(r.targetId)?.abort();
    if(r.type==='message_update'){
      const e=r.assistantMessageEvent;
      if(e?.type==='text_delta'){op.text+=e.delta;emit({type:'delta',kind:'assistant',text:e.delta});}
      if(e?.type==='thinking_delta')emit({type:'delta',kind:'thinking',text:e.delta});
    }
    if(r.type==='message_end' && r.message?.role==='assistant'){
      op.finals.set(r.messageId || op.finals.size,(r.message.content || []).filter(p=>p.type==='text').map(p=>p.text).join(''));
      op.final=[...op.finals.values()].join('');
    }
    if(r.type==='prompt_result' && r.id===op.nativeId)op.resolve(r);
    if(r.type==='session_settled')op.settle();
  }
});
async function hostCall(r,op){
  let result,isError=false;
  const call=new AbortController();
  try{
    if(!r.id || !r.toolCallId || op.seenCalls.has(r.id) || op.seenCalls.has(r.toolCallId) || seenCalls.has(r.id) || seenCalls.has(r.toolCallId) || !allowed.has(r.toolName))throw new Error('Unknown, duplicate or stale OMP host tool call.');
    for(const id of [r.id,r.toolCallId]){op.seenCalls.add(id);seenCalls.add(id);}
    // Retain every ID for this turn, plus a bounded recent cross-turn window.
    while(seenCalls.size>4096)seenCalls.delete(seenCalls.values().next().value);
    op.calls.set(r.id,call);
    const abort=()=>call.abort();op.abort.signal.addEventListener('abort',abort,{once:true});
    try{
      emit({type:'tool',name:r.toolName});
      result=await executeTool(config,r.toolName,r.arguments,call.signal);isError=result?.ok===false;
    }finally{op.abort.signal.removeEventListener('abort',abort);op.calls.delete(r.id);}
  }catch(error){result={ok:false,error:error.message};isError=true;}
  if(active===op && !op.cancelled)server.send({type:'host_tool_result',id:r.id,isError,result:{content:toolContent(result)}});
}
function ready(){return initializing ||= server.start(specs.map(t=>({name:t.name,label:t.name,description:t.description,parameters:t.inputSchema,loadMode:'essential'}))).then(()=>{
  const s=server.state;
  writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,model:s.model?.id,provider:s.model?.provider,reasoning_effort:s.thinkingLevel,tools:[...allowed].sort()}));
  emit({type:'backend',pid:server.pid});
}).catch(error=>{stopping=true;server.close();error.initializationFailed=true;throw error;});}
async function prompt(request,op){
  try{
    await ready();if(op.cancelled || active!==op)return;
    op.dispatched=true;
    // Prefix player text so it cannot invoke OMP's native slash commands.
    op.nativeId='gs-'+(server.serial+1);
    const completion=new Promise(resolve=>op.resolve=resolve);
    const admitted=await server.request('prompt',{message:'Player request:\n'+request.message});
    emit({type:'response',id:request.id,success:true});
    const result=admitted.agentInvoked===false ? {status:'completed'} : await completion;
    // The snapshot in prompt_result can already be true, but OMP still emits
    // its unkeyed settlement frame later. Consume it before admitting a turn.
    if(admitted.agentInvoked!==false)await op.settled;
    if(op.cancelled || active!==op)return;
    const state=await server.request('get_state');
    server.state=state;
    const tokens=state.contextUsage?.tokens;
    if(Number.isFinite(tokens) && tokens>=0)emit({type:'context',tokens});
    saveSession();
    const text=op.final ?? op.text;
    if(text.startsWith(op.text) && text.length>op.text.length)emit({type:'delta',kind:'assistant',text:text.slice(op.text.length)});
    emit({type:'complete',ok:result.status==='completed',text,corrected:!text.startsWith(op.text),error:result.status==='completed' ? '' : result.error?.message || 'OMP stopped: '+result.status});
  }catch(error){
    if(active===op && !op.cancelled)emit(op.dispatched ? {type:'complete',ok:false,text:op.text,error:error.message,initialization_failed:!!error.initializationFailed} : {type:'response',id:request.id,success:false,error:error.message,initialization_failed:!!error.initializationFailed});
  }finally{if(active===op)active=undefined;op.finish();}
}
async function cancel(request){
  cancelling=true;const op=active;
  if(op){op.cancelled=true;op.abort.abort();}
  try{
    if(op){await ready();if(op.dispatched){await server.request('abort_and_restore_queue');saveSession();}op.resolve?.({status:'aborted'});op.settle();await op.done;}
    emit({type:'response',id:request.id,success:true});
  }catch(error){emit({type:'response',id:request.id,success:false,error:error.message});}
  finally{cancelling=false;}
}
createInterface({input:process.stdin}).on('line',line=>{
  let r;try{r=JSON.parse(line);}catch{return;}
  if(r.type==='cancel'){if(!cancelling)void cancel(r);else emit({type:'response',id:r.id,success:false,error:'Already stopping OMP.'});return;}
  if(r.type!=='prompt' || active || stopping || cancelling){emit({type:'response',id:r.id,success:false,error:'OMP is busy or unavailable.'});return;}
  const op={request:r,text:'',finals:new Map(),abort:new AbortController(),calls:new Map(),seenCalls:new Set()};op.done=new Promise(resolve=>op.finish=resolve);op.settled=new Promise(resolve=>op.settle=resolve);active=op;void prompt(r,op);
});
process.stdin.on('end',()=>{stopping=true;active?.abort.abort();server.close();process.exit();});
