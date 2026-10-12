import { createInterface } from 'node:readline';
import { appendFile, writeFile } from 'node:fs/promises';
const emit=x=>process.stdout.write(JSON.stringify(x)+'\n');
const session='codex-fixture-thread';let serial=0,turn,interrupted=false,initialized=false,ready=false;
const pending=new Map();
function nativeRequest(method,params) {
  const id='request-'+ ++serial,result=new Promise(resolve=>pending.set(id,resolve));emit({id,method,params});return result;
}
async function tool(name,args={}) {
  const id='tool-'+ ++serial;
  emit({method:'item/started',params:{threadId:session,turnId:turn,item:{id,type:'dynamicToolCall',tool:'gamesmith_'+name,arguments:args}}});
  const result=new Promise(resolve=>pending.set(id,resolve));
  emit({id,method:'item/tool/call',params:{threadId:session,turnId:turn,callId:id,tool:'gamesmith_'+name,arguments:args}});
  const response=await result;emit({method:'item/completed',params:{threadId:session,turnId:turn,item:{id,type:'dynamicToolCall'}}});
  const data=JSON.parse(response.contentItems[0].text);
  if(data.ok===false) throw new Error(data.error || 'Tool failed');return data;
}
function notify(method,params={}) {emit({method,params:{threadId:session,turnId:turn,...params}});}
async function run(message) {
  try {
    notify('item/reasoning/summaryTextDelta',{itemId:'reasoning',delta:'Fixture thinking'});
    if (message==='wait' || message==='stuck-stop') return;
    if(message==='policy') {
      for(const method of ['item/fileChange/requestApproval','item/commandExecution/requestApproval']) {
        const response=await nativeRequest(method,{threadId:session,turnId:turn,itemId:'native'});
        if(response.decision!=='decline')throw new Error('Native approval escaped host policy');
      }
      const response=await nativeRequest('item/tool/call',{threadId:session,turnId:turn,callId:'outside',tool:'gamesmith_write',arguments:{path:'../outside.txt',content:'bad'}});
      if(response.success!==false)throw new Error('Workspace escape was accepted');
    }
    if(message==='reload' || message==='test') {
      await tool('write',{path:'main.gd',content:'extends Node\nvar fixture = true\n'});
      if(message==='test') {
        const tested=await tool('start_test_game',{mode:'headless'});await tool('read_test_log',{run_id:tested.run_id});await tool('stop_test_game',{run_id:tested.run_id});
      } else await tool('reload_game');
    }
    if(interrupted)return;
    if(message==='provider-error') {notify('turn/completed',{turn:{id:turn,status:'failed',error:{message:'Fixture provider error'},items:[]}});return;}
    notify('item/agentMessage/delta',{itemId:'answer',delta:'Fixture'});
    notify('thread/tokenUsage/updated',{tokenUsage:{last:{totalTokens:5120},total:{totalTokens:9999}}});
    notify('turn/completed',{turn:{id:turn,status:'completed',items:[{type:'agentMessage',id:'answer',text:'Fixture finished'}]}});
  } catch(error) {if(!interrupted)notify('turn/completed',{turn:{id:turn,status:'failed',error:{message:error.message},items:[]}});}
}
await writeFile('.codex-fixture-pids.json',JSON.stringify({cli:process.pid}));
createInterface({input:process.stdin}).on('line',async line=>{
  const r=JSON.parse(line);
  if(r.method) await appendFile('.codex-fixture-requests.jsonl',JSON.stringify(r)+'\n');
  if(!r.method && pending.has(r.id)){pending.get(r.id)(r.result);pending.delete(r.id);return;}
  if(r.method==='initialized'){ready=true;return;}
  const reply=result=>emit({id:r.id,result});
  if(r.method==='initialize'){if(process.env.GAMESMITH_CODEX_STUCK_START==='1')return;initialized=true;reply({userAgent:'fixture'});return;}
  if(!initialized || !ready){emit({id:r.id,error:{code:-32000,message:'Initialize handshake missing'}});return;}
  switch(r.method) {
    case 'config/read': reply({config:{mcp_servers:{unrelated:{enabled:true}}}});break;
    case 'thread/start':
      if(!r.params.dynamicTools.some(t=>t.type==='function' && t.name==='gamesmith_reload_game')) throw new Error('Missing tools');
      reply({thread:{id:session}});break;
    case 'thread/resume':
      if(r.params.threadId!==session) throw new Error('Wrong native thread');reply({thread:{id:session}});break;
    case 'turn/start':
      turn='turn-'+ ++serial;interrupted=false;reply({turn:{id:turn,status:'inProgress'}});setImmediate(()=>run(r.params.input[0].text));break;
    case 'turn/interrupt':
      if(process.env.GAMESMITH_CODEX_STUCK_STOP==='1')return;
      interrupted=true;reply({});if(process.env.GAMESMITH_CODEX_STUCK_SETTLE!=='1')notify('turn/completed',{turn:{id:turn,status:'interrupted',items:[]}});break;
    default:emit({id:r.id,error:{code:-32601,message:'Unsupported method: '+r.method}});
  }
});
process.stdin.on('end',()=>process.exit());
