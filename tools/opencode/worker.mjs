import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline';
import { buildConfig, normalizeFrame } from './protocol.mjs';
import { OpenCodeServer } from './server.mjs';
import { createEventNormalizer } from './events.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const harness=config.harness || 'opencode', label=harness==='kilo' ? 'Kilo' : 'OpenCode', prefix=harness==='kilo' ? 'KILO' : 'OPENCODE';
const emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
let session=config.session || '', contextTokens=config.context_tokens ?? null;
let active, initializing, cancelling=false, stopping=false;
function saveSession() {
  if (!session) return;
  writeFileSync(config.session_file+'.tmp',JSON.stringify({session,context_tokens:contextTokens}));
  renameSync(config.session_file+'.tmp',config.session_file);
}
const existing=JSON.parse(process.env[prefix+'_CONFIG_CONTENT'] || '{}'), host=buildConfig(config);
const inline={...existing,...host,plugin:[...(existing.plugin || []),...host.plugin],instructions:[...(existing.instructions || []),...host.instructions],mcp:{...existing.mcp,...host.mcp}};
const server=new OpenCodeServer({workspace:config.workspace,harness,env:{...process.env,[prefix+'_CONFIG_CONTENT']:JSON.stringify(inline),GAMESMITH_HOST_BRIDGE_DIR:config.bridge_dir},
  onStderr:line=>process.stderr.write(line+'\n'),onExit:error=>{if (!stopping) emit({type:'integration_error',error:error.message});}});
function emitRecords(records,operation) {
  for (const record of records) {
    if (record.session) {session=record.session;saveSession();}
    if (record.type==='context') {contextTokens=record.tokens;saveSession();}
    if (record.type==='assistant_text') {operation.text+=record.text;continue;}
    if (record.type==='integration_error') operation.error=record.error;
    if (record.type==='transcript_reconcile') {operation.corrected=true;continue;}
    emit(record);
  }
}
function records(frame,operation) {emitRecords(normalizeFrame(frame,label),operation);}
function ready() {
  return initializing ||= (async()=>{
    await server.start();
    writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,url:server.url}));
    if (session) {
      try {await server.request('/session/'+session);}
      catch(error) {
        if(harness==='kilo')error.message='Kilo session could not be resumed: '+error.message+'. Start a new Kilo session in Settings. The previous session reference and chat are kept.';
        throw error;
      }
    }
    else session=(await server.request('/session','POST',{title:config.name})).id;
    saveSession();emit({type:'session',session});
  })().catch(async error=>{
    error.initializationFailed=true;
    if(harness==='kilo'){stopping=true;await server.close();}
    throw error;
  });
}
async function prompt(request,operation) {
  let unsubscribe;
  try {
    await ready();if (operation.cancelled) return;
    const status=await server.request('/session/status');
    if (status[session]?.type && status[session].type!=='idle') throw new Error(label+' session is already busy.');
    const normalizeEvent=createEventNormalizer(session,label);
    unsubscribe=await server.subscribe(event=>{
      if (active!==operation || operation.cancelled) return;
      const properties=event.properties || {};
      if (event.type==='permission.asked' && properties.sessionID===session) {
        server.request('/permission/'+properties.id+'/reply','POST',{reply:'once'}).catch(error=>{operation.error=error.message;});return;
      }
      emitRecords(normalizeEvent(event),operation);
    },error=>{if (!operation.cancelled) process.stderr.write(label+' event stream interrupted: '+error.message+'\n');});
    if (operation.cancelled) return;
    emit({type:'response',id:request.id,success:true});operation.accepted=true;
    const result=await server.request('/session/'+session+'/message','POST',{parts:[{type:'text',text:request.message}]});
    if (operation.cancelled) return;
    if (result.info?.modelID) writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,url:server.url,model:result.info.providerID+'/'+result.info.modelID,variant:result.info.variant}));
    if (result.info?.error) operation.error=result.info.error.data?.message || result.info.error.message || result.info.error.name;
    emitRecords(normalizeEvent.reconcile(result),operation);
    records({type:'step_finish',part:{tokens:result.info?.tokens}},operation);
    const text=(result.parts || []).filter(p=>p.type==='text').map(p=>p.text).join('');
    const ok=result.info?.finish==='stop' && !operation.error;
    emit({type:'complete',ok,text,corrected:!!operation.corrected,error:operation.error || (ok ? '' : label+' ended without a completed response.')});
  } catch(error) {
    if (!operation.cancelled) emit(operation.accepted ? {type:'complete',ok:false,text:operation.text,error:error.message,initialization_failed:!!error.initializationFailed} : {type:'response',id:request.id,success:false,error:error.message,initialization_failed:!!error.initializationFailed});
  } finally {unsubscribe?.();if (active===operation) active=undefined;}
}
async function cancel(request) {
  if (cancelling) {emit({type:'response',id:request.id,success:false,error:'Cancellation is already in progress.'});return;}
  cancelling=true;const operation=active;if (operation) operation.cancelled=true;
  try {
    if (initializing) await initializing;
    if (session && server.url) await server.request('/session/'+session+'/abort','POST');
    await operation?.done;
    emit({type:'response',id:request.id,success:true});
  } catch(error) {emit({type:'response',id:request.id,success:false,error:error.message});}
  finally {cancelling=false;}
}
createInterface({input:process.stdin}).on('line',line=>{
  let request;try {request=JSON.parse(line);} catch {return;}
  if (request.type==='cancel') {void cancel(request);return;}
  if (request.type!=='prompt' || active || cancelling || stopping) {emit({type:'response',id:request.id,success:false,error:label+' is busy or command is unsupported.'});return;}
  const operation={text:'',error:'',cancelled:false};active=operation;operation.done=prompt(request,operation);
});
process.stdin.on('end',async()=>{
  stopping=true;if (active) active.cancelled=true;
  // Kill the complete backend tree even when a native request is blocked.
  await server.close();process.exit();
});
