import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {AgyServer} from './server.mjs';
import {normalizeRecord,reconcileText} from './protocol.mjs';
const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let session=config.session || '',active,started=false,stopping=false;
const stateFile=join(config.bridge_dir,'operation.json');
function state(enabled){writeFileSync(stateFile+'.tmp',JSON.stringify({active:enabled,session}));renameSync(stateFile+'.tmp',stateFile);}
state(false);
function finish(ok,error='',final,initializationFailed=false) {
  if(!active)return;
  const operation=active;active=undefined;state(false);
  const result=reconcileText(operation.text,final);
  if(result.suffix)emit({type:'delta',kind:'assistant',text:result.suffix});
  if(!ok){stopping=true;server.close();}
  emit(operation.accepted ? {type:'complete',ok,text:result.text,corrected:result.corrected,error,runtime_failed:!ok,initialization_failed:initializationFailed}
    : {type:'response',id:operation.request.id,success:false,error,initialization_failed:true});
}
const server=new AgyServer(config,{
  onStderr:line=>process.stderr.write(line+'\n'),
  onExit:error=>finish(false,session ? 'AGY request failed: '+error.message+'. If the saved conversation cannot be resumed, start a new AGY session in Settings; its previous reference and chat are kept.' : error.message),
  onRecord:record=>{
    if(!active || stopping)return;
    if(record.event==='init'){
      const id=record.conversation_id;
      if(typeof id!=='string' || !id || (session && id!==session)){
        finish(false,'AGY session could not be resumed. Start a new AGY session in Settings. The previous reference and chat are kept.',undefined,true);return;
      }
      session=id;state(true);
      writeFileSync(config.session_file+'.tmp',JSON.stringify({session}));renameSync(config.session_file+'.tmp',config.session_file);
      writeFileSync(join(dirname(config.session_file),'backend.json'),JSON.stringify({pid:server.pid,session}));
      emit({type:'session',session});return;
    }
    const id=record.step_update?.conversation_id || record.result?.conversation_id;
    if(!session || id!==session)return;
    for(const r of normalizeRecord(record)){
      if(r.type==='tool' && Number.isInteger(record.step_update.step_index)){
        if(active.toolSteps.has(record.step_update.step_index))continue;
        active.toolSteps.add(record.step_update.step_index);
      }
      if(r.type==='delta')active.text+=r.text;emit(r);
    }
    if(record.event==='result'){
      const result=record.result;
      finish(result.status==='SUCCESS',result.error || (result.status==='SUCCESS'?'':'AGY stopped: '+result.status),result.response);
    }
  }
});
createInterface({input:process.stdin}).on('line',async line=>{
  let request;try{request=JSON.parse(line);}catch{return;}
  if(request.type==='cancel'){
    stopping=true;active=undefined;state(false);server.close();emit({type:'response',id:request.id,success:true});return;
  }
  if(request.type!=='prompt' || active || stopping){emit({type:'response',id:request.id,success:false,error:'AGY is busy or must be restarted.'});return;}
  const operation={text:'',request,toolSteps:new Set()};active=operation;
  try {
    if(!started){await server.start();started=true;}
    if(active!==operation || stopping)return;
    // init arrives only after a user record, so acceptance precedes native init.
    operation.accepted=true;emit({type:'response',id:request.id,success:true});state(!!session);
    server.prompt(readFileSync(config.prompt_path,'utf8')+'\n\nPlayer request:\n'+request.message);
  }catch(error){
    if(active!==operation)return;active=undefined;state(false);stopping=true;server.close();
    emit({type:'response',id:request.id,success:false,error:error.message,initialization_failed:true});
  }
});
process.stdin.on('end',()=>{stopping=true;state(false);server.close();process.exit();});
