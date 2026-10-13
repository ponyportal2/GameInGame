import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {createInterface} from 'node:readline';
import {CommandServer} from './server.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let session=config.session_id || config.session || '', context=config.context_tokens ?? null;
let server, initializing, active, commands=new Set(), outcome;
const commandUpdates = new Map();
function save(){if(!session)return;writeFileSync(config.session_file+'.tmp',JSON.stringify({session,context_tokens:context}));renameSync(config.session_file+'.tmp',config.session_file);}
function retire(){server?.close();server=undefined;initializing=undefined;commands.clear();commandUpdates.clear();}
function update(method,p){
  if(method!=='session/update')return;
  const u=p.update;
  if(u.sessionUpdate==='available_commands_update'){const names=new Set((u.availableCommands || []).map(c=>c.name));commandUpdates.set(p.sessionId,names);if(p.sessionId===session)commands=names;return;}
  if(p.sessionId!==session)return;
  if(u.sessionUpdate==='usage_update' && Number.isFinite(u.used)){context=u.used;save();emit({type:'context',tokens:context});return;}
  if(!active?.accepted || active.compact)return;
  if(['agent_message_chunk','agent_thought_chunk'].includes(u.sessionUpdate) && u.content?.type==='text'){
    const kind=u.sessionUpdate==='agent_message_chunk'?'assistant':'thinking';
    if(kind==='assistant')active.text+=u.content.text;
    emit({type:'delta',kind,text:u.content.text});
  }else if(u.sessionUpdate==='tool_call')emit({type:'tool',name:u.title || 'tool',description:''});
  else if(u.sessionUpdate==='tool_call_update' && ['completed','failed'].includes(u.status))emit({type:'status',text:'Command-code is working…'});
}
function policy(event){
  if(event.type==='compaction_outcome')outcome=event;
  if(event.type==='compaction_start')emit({type:'status',text:'Command-code is compacting context…'});
  if(event.type==='mod_error'){
    const error=new Error('GameSmith policy mod failed: '+(event.error || event.message || JSON.stringify(event)));
    if(active)active.error=error;
    server?.close();
  }
}
async function ready(){
  if(initializing)return initializing;
  initializing=(async()=>{
    const runtime=new CommandServer(config,{onEvent:update,onPolicy:policy,onStderr:line=>process.stderr.write(line+'\n'),
      onExit:()=>{},onRequest:(method,p)=>{
        if(method==='session/request_permission'){
          const option=p.options?.find(o=>o.kind==='reject_once');
          return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
        }
        throw new Error('GameSmith does not provide native terminal/filesystem services.');
      }});
    server=runtime;
    let timer;
    const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Command-code GameSmith integration did not become ready. Use tested version 1.82.1; no model request was sent.')),config.startup_timeout_ms || 20000);});
    try{await Promise.race([(async()=>{
      await runtime.start();
      if(session){
        const listed=await runtime.request('session/list',{cwd:config.workspace});
        if(!listed.sessions?.some(s=>s.sessionId===session))throw new Error('Saved Command-code session cannot be resumed here. Use Start a new Command-code session in Settings to recover.');
      }
      const method=session?'session/load':'session/new';
      const result=await runtime.request(method,{...(session?{sessionId:session}:{}),cwd:config.workspace,mcpServers:[]});
      if(session && result.sessionId && result.sessionId!==session)throw new Error('Command-code resumed a different native session.');
      session=result.sessionId || session;if(!session)throw new Error('Command-code did not return a native session ID.');
      commands=commandUpdates.get(session) || commands;
      while(!commands.has(runtime.readyCommand)){if(runtime.closing)throw new Error('Command-code stopped during session initialization.');await new Promise(r=>setTimeout(r,20));}
      await runtime.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:'/'+runtime.readyCommand}]});
      await runtime.waitReady('session');
      // Same unattended native permission mode as the former --yolo transport.
      // Our verified in-process mod remains the tool/path policy boundary.
      await runtime.request('session/set_mode',{sessionId:session,modeId:'bypass'});save();
      emit({type:'backend',pid:runtime.pid,session});
    })(),deadline]);}catch(error){retire();throw error;}finally{clearTimeout(timer);}
  })();
  return initializing;
}
createInterface({input:process.stdin}).on('line',async line=>{
  let r;try{r=JSON.parse(line);}catch{return;}
  if(r.type==='cancel'){active && (active.cancelled=true);retire();emit({type:'response',id:r.id,success:true});return;}
  if(!['prompt','compact'].includes(r.type) || active){emit({type:'response',id:r.id,success:false,error:'Command-code is busy or command is unsupported.'});return;}
  if(r.type==='compact' && !session){emit({type:'response',id:r.id,success:false,data:{ok:false,no_op:true},error:'No saved Command-code conversation to compact.'});return;}
  const operation={text:'',accepted:false,compact:r.type==='compact'};active=operation;
  try{
    await ready();if(operation.cancelled)return;
    outcome=undefined;
    if(!operation.compact){operation.accepted=true;emit({type:'response',id:r.id,success:true});}
    const result=await server.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:operation.compact?'/compact':r.message}]});
    if(operation.error)throw operation.error;if(operation.cancelled)return;
    save();
    if(operation.compact){
      if(!outcome || !['summarized','too-small','failed'].includes(outcome.outcome))throw new Error('Command-code did not report a known native compaction outcome.');
      const data={ok:outcome.outcome!=='failed',no_op:outcome.outcome==='too-small',tokens_before:outcome.tokensBefore,tokens_after:context,
        error:outcome.outcome==='failed'?'Native Command-code summarization failed; history was kept.':outcome.outcome==='too-small'?'Conversation is too small to compact.':''};
      emit({type:'response',id:r.id,success:data.ok,data,error:data.error});
    }else emit({type:'complete',ok:result.stopReason==='end_turn',text:operation.text,error:result.stopReason==='end_turn'?'':'Command-code stopped: '+result.stopReason});
  }catch(error){
    if(!operation.cancelled){const initialization_failed=!operation.accepted;retire();const message=error.message+(session && initialization_failed?' Saved conversation was kept; check native Command-code session availability.':'');
      emit(operation.accepted?{type:'complete',ok:false,text:operation.text,error:message,initialization_failed:true}:{type:'response',id:r.id,success:false,error:message,initialization_failed,data:{ok:false,error:message}});}
  }finally{if(active===operation)active=undefined;}
});
process.stdin.on('end',()=>{retire();process.exit();});
