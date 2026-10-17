import { createInterface } from 'node:readline';
import { readFile, writeFile, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { hostTools, toolContent, executeHostTool } from './host-tools.mjs';

const abort = new AbortController();
async function callHost(command,args) {
  const directory = process.env.GAMESMITH_HOST_BRIDGE_DIR;
  if (!directory) throw new Error('GameSmith bridge is unavailable.');
  const id = randomUUID();
  const request = join(directory,`request-${id}.json`);
  const response = join(directory,`response-${id}.json`);
  await writeFile(request+'.tmp',JSON.stringify({id,command,args}));
  await rename(request+'.tmp',request);
  while (!abort.signal.aborted) {
    try { const result=JSON.parse(await readFile(response,'utf8')); await rm(response); return result; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw new Error('GameSmith tool cancelled.');
}
const emit = response=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',...response})+'\n');
createInterface({input:process.stdin}).on('line',async line=>{
  let request;
  try { request=JSON.parse(line); } catch { return; }
  if (request.id === undefined) return;
  try {
    let result;
    switch (request.method) {
      case 'initialize': result={protocolVersion:request.params?.protocolVersion || '2024-11-05',capabilities:{tools:{}},serverInfo:{name:'gamesmith',version:'1.0.0'}}; break;
      case 'ping': result={}; break;
      case 'tools/list': result={tools:Object.entries(hostTools).map(([name,t])=>({name,description:t.description,inputSchema:{type:'object',properties:t.properties,required:t.required || []}}))}; break;
      case 'tools/call': {
        const name=request.params?.name;
        if (!Object.hasOwn(hostTools,name)) throw new Error('Unknown GameSmith tool: '+name);
        // OpenCode resets the native MCP deadline on progress. Keep approval
        // waits alive indefinitely, without increasing or inventing a timeout.
        const token=request.params?._meta?.progressToken;
        let progress=0;
        const heartbeat=token === undefined ? undefined : setInterval(()=>emit({method:'notifications/progress',params:{progressToken:token,progress:++progress}}),1000);
        let response;
        try { response=await executeHostTool(name,request.params.arguments || {},{workspace:process.cwd(),callHost,signal:abort.signal}); }
        finally { clearInterval(heartbeat); }
        result={content:toolContent(response),isError:response.ok === false};
        break;
      }
      default: emit({id:request.id,error:{code:-32601,message:'Method not found'}}); return;
    }
    emit({id:request.id,result});
  } catch (error) {
    if (request.method === 'tools/call') emit({id:request.id,result:{isError:true,content:[{type:'text',text:error.message}]}});
    else emit({id:request.id,error:{code:-32603,message:error.message}});
  }
});
process.stdin.on('end',()=>{abort.abort();process.exit();});
