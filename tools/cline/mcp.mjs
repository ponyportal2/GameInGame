import {createInterface} from 'node:readline';
import {readFileSync} from 'node:fs';
import {toolSpecs,executeTool} from './workspace-tools.mjs';
import {toolContent} from './host-tools.mjs';
import {consumeReloadGrant} from './approval.mjs';
const config=JSON.parse(readFileSync(process.argv[2],'utf8')),abort=new AbortController();
const emit=r=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',...r})+'\n');
createInterface({input:process.stdin}).on('line',async line=>{
  let r;try{r=JSON.parse(line);}catch{return;}if(r.id===undefined)return;
  try {
    let result;
    switch(r.method){
      case 'initialize':result={protocolVersion:r.params?.protocolVersion || '2024-11-05',capabilities:{tools:{}},serverInfo:{name:'gamesmith',version:'1.0.0'}};break;
      case 'ping':result={};break;
      case 'tools/list':result={tools:toolSpecs().map(t=>({name:t.name.slice(10),description:t.description,inputSchema:t.inputSchema}))};break;
      case 'tools/call':{
        const token=r.params?._meta?.progressToken;let progress=0;
        const heartbeat=token===undefined ? undefined : setInterval(()=>emit({method:'notifications/progress',params:{progressToken:token,progress:++progress}}),1000);
        try {
          const args={...r.params.arguments};
          if(r.params.name==='reload_game')args.approval_token=await consumeReloadGrant(config);
          const data=await executeTool(config,'gamesmith_'+r.params.name,args,abort.signal);result={content:toolContent(data),isError:data.ok===false};
        }
        finally{clearInterval(heartbeat);}break;
      }
      default:emit({id:r.id,error:{code:-32601,message:'Method not found'}});return;
    }
    emit({id:r.id,result});
  }catch(error){emit({id:r.id,result:{isError:true,content:[{type:'text',text:error.message}]}});}
});
process.stdin.on('end',()=>{abort.abort();process.exit();});
