import { readFileSync, writeFileSync, renameSync, realpathSync, rmSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { buildConfig, mergeConfig, normalizeFrame } from './protocol.mjs';
import { OpenCodeAcpServer, OpenCodeServer } from './server.mjs';
import { createAcpNormalizer, createEventNormalizer } from './events.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const harness=config.harness || 'opencode', acp=harness!=='kilo';
const label=acp ? 'OpenCode' : 'Kilo', prefix=acp ? 'OPENCODE' : 'KILO';
const emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
let session=config.session || '', contextTokens=config.context_tokens ?? null, backendModel='';
let active, initializing, cancelling=false, stopping=false;
function saveSession() {
  if (!session) return;
  writeFileSync(config.session_file+'.tmp',JSON.stringify({session,context_tokens:contextTokens}));
  renameSync(config.session_file+'.tmp',config.session_file);
}
function writeBackend(extra={}) {
  writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,...(backendModel ? {model:backendModel} : {}),...extra}));
}
const inline=mergeConfig(JSON.parse(process.env[prefix+'_CONFIG_CONTENT'] || '{}'),buildConfig(config),harness);
const guard=acp ? {path:join(dirname(config.session_file),'guard-'+randomBytes(16).toString('hex')+'.json'),token:randomBytes(16).toString('hex')} : null;
const shared={workspace:config.workspace,env:{...process.env,[prefix+'_CONFIG_CONTENT']:JSON.stringify(inline),...(guard ? {GAMESMITH_OPENCODE_GUARD:JSON.stringify(guard)} : {}),GAMESMITH_HOST_BRIDGE_DIR:config.bridge_dir},
  onStderr:line=>process.stderr.write(line+'\n'),onExit:error=>{if (!stopping) emit({type:'integration_error',error:error.message});}};
const server=acp ? new OpenCodeAcpServer(shared) : new OpenCodeServer({...shared,harness});
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
async function adoptOptions(result) {
  const options=result?.configOptions || [];
  const model=options.find(option=>option.id==='model');
  if (model?.currentValue) backendModel=model.currentValue;
  const mode=options.find(option=>option.id==='mode');
  // A resumed session keeps the agent it was created with, and a player-wide
  // default agent would bypass the confined rule set. Pin the confined agent.
  if (!mode) throw new Error('OpenCode did not report its active agent; refusing an unconfined session.');
  if (mode.currentValue!=='build') {
    const updated=await server.request('session/set_config_option',{sessionId:session,configId:'mode',value:'build'});
    if (!updated?.configOptions?.some(option=>option.id==='mode' && option.currentValue==='build')) throw new Error('OpenCode did not activate the confined build agent.');
    const next=(updated?.configOptions || []).find(option=>option.id==='model');
    if (next?.currentValue) backendModel=next.currentValue;
  }
}
function ready() {
  return initializing ||= (async()=>{
    await server.start();
    writeBackend(acp ? {} : {url:server.url});
    if (acp) {
      if (session) {
        let loaded;
        try {loaded=await server.request('session/load',{sessionId:session,cwd:config.workspace,mcpServers:[]});}
        catch(error) {error.message='OpenCode session could not be resumed: '+error.message+'. Start a new OpenCode session in Settings. The previous session reference and chat are kept.';throw error;}
        await adoptOptions(loaded);
      } else {
        const created=await server.request('session/new',{cwd:config.workspace,mcpServers:[]});
        session=created.sessionId;
        await adoptOptions(created);
      }
      try {
        const loaded=JSON.parse(readFileSync(guard.path,'utf8'));
        // OpenCode may run the plugin in its own server subprocess. The fresh
        // secret and canonical workspace bind this acknowledgement to our run.
        if (loaded.token!==guard.token || !Number.isInteger(loaded.pid) || resolve(loaded.directory)!==realpathSync(config.workspace)) throw new Error('Invalid workspace guard acknowledgement.');
      } catch (error) { throw new Error('OpenCode workspace guard was not loaded; refusing to run: '+error.message); }
      finally {rmSync(guard.path,{force:true});}
      writeBackend();
    } else {
      if (session) {
        try {await server.request('/session/'+session);}
        catch(error) {
          error.message='Kilo session could not be resumed: '+error.message+'. Start a new Kilo session in Settings. The previous session reference and chat are kept.';
          throw error;
        }
      }
      else session=(await server.request('/session','POST',{title:config.name})).id;
    }
    saveSession();emit({type:'session',session});
  })().catch(async error=>{
    error.initializationFailed=true;
    stopping=true;await server.close();
    if (guard) rmSync(guard.path,{force:true});
    throw error;
  });
}
async function prompt(request,operation) {
  let unsubscribe;
  try {
    await ready();if (operation.cancelled) return;
    if (acp) {
      const normalizeUpdate=createAcpNormalizer(label);
      unsubscribe=server.onUpdate(update=>{
        if (active!==operation || operation.cancelled) return;
        emitRecords(normalizeUpdate(update),operation);
      });
      emit({type:'response',id:request.id,success:true});operation.accepted=true;
      // usage_update is the only source of context occupancy. The prompt
      // result's usage.totalTokens measures this call's consumption, not what
      // the session now holds, so it is never substituted for a missing or
      // unchanged measurement.
      const result=await server.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:request.message}]});
      if (operation.cancelled) return;
      const ok=result?.stopReason==='end_turn' && !operation.error;
      emit({type:'complete',ok,text:operation.text,corrected:!!operation.corrected,error:operation.error || (ok ? '' : label+' ended without a completed response.')});
      return;
    }
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
    if (result.info?.modelID) {
      backendModel=result.info.providerID+'/'+result.info.modelID;
      writeBackend({url:server.url,model:backendModel,variant:result.info.variant});
    }
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
    if (acp) {if (session && server.running) server.notify('session/cancel',{sessionId:session});}
    else if (session && server.url) await server.request('/session/'+session+'/abort','POST');
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
  await server.close();if (guard) rmSync(guard.path,{force:true});process.exit();
});
