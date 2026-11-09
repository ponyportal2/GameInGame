import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createInterface} from 'node:readline';
import {ClaudeServer} from './server.mjs';
import {toolSpecs} from './workspace-tools.mjs';
import {atomicSaveSession,failureRecord} from './session-state.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
const allowed=new Set(toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10)));
let session=config.session || '',saved=!!session,active,initialized=false,started=false,stopping=false,model='',usage={};
function state(enabled){const path=join(config.bridge_dir,'operation.json');writeFileSync(path+'.tmp',JSON.stringify({active:enabled,session}));renameSync(path+'.tmp',path);}
state(false);
function save(){if(!saved){atomicSaveSession(config.session_file,{session});saved=true;emit({type:'session',session});}}
function retire(error){
  if(stopping)return;stopping=true;state(false);server.close();
  if(active){error.initializationFailed=!active.accepted;error.runtimeFailed=true;
    if(config.session && !active.accepted)error.message='Claude Code session could not be resumed: '+error.message+'. Start a new Claude Code session in Settings. The previous session reference and chat are kept.';
    emit(failureRecord(active,error,{requestPreserved:active.requestPreserved}));active=undefined;}
}
function record(r){
  if(stopping)return;
  if(r.type==='system' && r.subtype==='init'){
    if(!r.session_id || (session && r.session_id!==session))throw new Error('Claude Code resumed a different or missing session.');
    if(!Array.isArray(r.tools) || r.tools.some(t=>!allowed.has(t)))throw new Error('Claude Code exposed tools outside the GameSmith MCP registry.');
    const missing=[...allowed].filter(t=>!r.tools.includes(t));
    if(missing.length)throw new Error('Claude Code did not connect the complete GameSmith MCP registry: '+missing.join(', '));
    session=r.session_id;model=r.model;initialized=true;
    writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,model}));
    emit({type:'backend',pid:server.pid});
    state(!!active);
    if(active && !active.accepted){active.accepted=true;emit({type:'response',id:active.request.id,success:true});}
    return;
  }
  if(!active)return;
  if(r.session_id && session && r.session_id!==session)throw new Error('Claude Code stream session identity changed.');
  if(r.type==='user' && r.uuid===active.uuid){active.requestPreserved=true;save();return;}
  if(r.type==='assistant'){
    // Replay records are not new output; assistant snapshots reconcile missing chunks.
    if(r.isReplay)return;
    active.snapshot=(r.message?.content || []).filter(c=>c.type==='text').map(c=>c.text).join('');
    return;
  }
  if(r.type==='stream_event' && !r.parent_tool_use_id){
    const e=r.event || {},d=e.delta || {};
    if(e.type==='message_start')usage=e.message?.usage || {};
    if(e.type==='message_delta'){
      usage={...usage,...e.usage};const tokens=(usage.input_tokens||0)+(usage.cache_read_input_tokens||0)+(usage.cache_creation_input_tokens||0)+(usage.output_tokens||0);
      if(tokens)emit({type:'context',tokens});
    }
    if(d.type==='text_delta'){active.text+=d.text;emit({type:'delta',kind:'assistant',text:d.text});}
    if(d.type==='thinking_delta')emit({type:'delta',kind:'thinking',text:d.thinking});
    if(e.type==='content_block_start' && e.content_block?.type==='tool_use'){
      if(!allowed.has(e.content_block.name))throw new Error('Claude Code requested a tool outside the GameSmith registry.');
      emit({type:'tool',name:e.content_block.name,status:'running'});
    }
  }
  if(r.type==='result'){
    const ok=initialized && r.subtype==='success' && !r.is_error;
    if(!active.accepted){retire(new Error((r.errors || []).join('\n') || r.result || 'Claude Code failed before initialization.'));return;}
    active.requestPreserved=true;save();state(false);
    const text=r.result ?? active.snapshot ?? active.text;
    emit({type:'complete',ok,text,corrected:!!active.text && text!==active.text,request_preserved:true,error:ok?'':(r.errors || []).join('\n') || r.result || 'Claude Code stopped: '+r.subtype});active=undefined;
  }
}
const server=new ClaudeServer(config,{onRecord:r=>{try{record(r);}catch(error){retire(error);}},onExit:retire,onStderr:line=>process.stderr.write(line+'\n')});
createInterface({input:process.stdin}).on('line',line=>{
  let r;try{r=JSON.parse(line);}catch{return;}
  if(r.type==='cancel'){
    state(false);active=undefined;stopping=true;server.close();emit({type:'response',id:r.id,success:true});return;
  }
  if(r.type!=='prompt' || active || stopping){emit({type:'response',id:r.id,success:false,error:'Claude Code is busy or unavailable.'});return;}
  active={request:r,uuid:randomUUID(),accepted:false,requestPreserved:false,text:''};
  try{
    if(!started){started=true;server.start();}
    if(initialized){active.accepted=true;state(true);emit({type:'response',id:r.id,success:true});}
    server.send({type:'user',uuid:active.uuid,message:{role:'user',content:r.message}});
  }catch(error){retire(error);}
});
process.stdin.on('end',()=>{stopping=true;state(false);server.close();process.exit();});
