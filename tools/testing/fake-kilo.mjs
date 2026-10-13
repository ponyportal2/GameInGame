import { writeFile, readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

import http from 'node:http';
let currentResponse;
const subscribers=new Set();
const parts=[];
let partId=0;
let waiting;
let aborted=false;
const session='ses_fixture';
const emit=frame=>{
 const type={step_start:'step-start',step_finish:'step-finish',tool_use:'tool',text:'text',reasoning:'reasoning'}[frame.type];
 if (!type) return;
 const part={...frame.part,id:String(++partId),sessionID:session,type,time:{end:Date.now()}};parts.push(part);
 for (const response of subscribers) response.write('data: '+JSON.stringify({type:'message.part.updated',properties:{part}})+'\n\n');
};
const config=JSON.parse(process.env.KILO_CONFIG_CONTENT);
const hooks=config.plugin[0] ? await (await import(config.plugin[0])).default({directory:process.cwd()}) : {'tool.execute.before':async()=>{}};
const mcp=config.mcp.gamesmith ? spawn(config.mcp.gamesmith.command[0],config.mcp.gamesmith.command.slice(1),{windowsHide:true,stdio:['pipe','pipe','pipe'],env:process.env}) : null;
await writeFile('.kilo-fixture-pids.json',JSON.stringify({cli:process.pid,mcp:mcp?.pid}));
const pending=new Map();let id=0;
if (mcp) createInterface({input:mcp.stdout}).on('line',line=>{
  const frame=JSON.parse(line);
  if (pending.has(frame.id)) {pending.get(frame.id)(frame);pending.delete(frame.id);}
});
mcp?.stderr.pipe(process.stderr);
function request(method,params) {
  const next=++id;
  const result=new Promise(resolve=>pending.set(next,resolve));
  mcp.stdin.write(JSON.stringify({jsonrpc:'2.0',id:next,method,params})+'\n');return result;
}
if (mcp) {await request('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'fixture',version:'1'}});
const listed=await request('tools/list',{});
if (!listed.result.tools.find(t=>t.name==='reload_game')) throw new Error('MCP missing host tools');}
async function host(name,args={}) {
  await hooks['tool.execute.before']({tool:'gamesmith_'+name},{args});
  const frame=await request('tools/call',{name,arguments:args,_meta:{progressToken:String(id+1)}});
  emit({type:'tool_use',part:{tool:'gamesmith_'+name,state:{status:frame.result.isError?'error':'completed'}}});
  return JSON.parse(frame.result.content[0].text);
}
async function run(prompt) {
 parts.length=0;aborted=false;
 emit({type:'step_start',part:{}});
 if (prompt==='wait') {
   const reasoning={id:'live-reasoning',sessionID:session,messageID:'live-assistant',type:'reasoning',text:'',time:{start:Date.now()}};
   for (const response of subscribers) {
     response.write('data: '+JSON.stringify({type:'message.part.updated',properties:{part:reasoning}})+'\n\n');
     response.write('data: '+JSON.stringify({type:'message.part.delta',properties:{sessionID:session,partID:reasoning.id,field:'text',delta:'Fixture is thinking before completion'}})+'\n\n');
   }
   return await new Promise(resolve=>waiting=resolve);
 }
 if (prompt==='partial-stream' || prompt==='lost-stream') {
   emit({type:'text',part:{text:'I changed the player'}});
   if (prompt==='lost-stream') for (const response of subscribers) response.destroy();
   return {info:{finish:'stop'},parts:[{id:String(partId),sessionID:session,type:'text',text:'I changed the player movement and fixed collisions.'}]};
 }
 if (prompt==='stuck-abort' || prompt==='settle-stall') return await new Promise(()=>{});
 if (prompt==='provider-error') return {info:{error:{data:{message:'Fixture provider error'}}},parts:[]};
 if (prompt==='incomplete') return {info:{},parts:[]};
 if (prompt==='tool-round-only') return {info:{finish:'tool-calls'},parts:[]};
if (prompt==='reload') {
  await writeFile('main.gd','extends Node\n');
  const result=await host('reload_game');if (!result.ok) throw new Error(result.error);
}
if (prompt==='test') {
  await writeFile('main.gd','extends Node\n');
  const result=await host('start_test_game',{mode:'headless'});if (!result.ok) throw new Error(result.error);
  const stopped=await host('stop_test_game',{run_id:result.run_id});if (stopped.state!=='exited') throw new Error('Test did not exit');
}
if (prompt==='repair-reload') {
  await writeFile('main.gd','extends Node\nfunc broken(:\n');
  const failed=await host('reload_game');if (failed.ok || !failed.diagnostics) throw new Error('Missing reload diagnostics');
  await writeFile('main.gd','extends Node\nvar repaired = true\n');
  const tested=await host('start_test_game',{mode:'headless'});if (!tested.ok) throw new Error(tested.error);
  await host('read_test_log',{run_id:tested.run_id});await host('stop_test_game',{run_id:tested.run_id});
  const reloaded=await host('reload_game');if (!reloaded.ok) throw new Error(reloaded.error);
}
emit({type:'text',part:{text:'Fixture finished'}});
emit({type:'step_finish',part:{reason:'stop',tokens:{total:5120,input:100,output:20,cache:{read:5000,write:0}}}});
return {info:{finish:'stop',tokens:{total:5120,input:100,output:20,cache:{read:5000,write:0}}},parts:[...parts]};
}
const server=http.createServer(async(req,res)=>{
 if (req.headers.authorization!=='Basic '+Buffer.from('kilo:'+process.env.KILO_SERVER_PASSWORD).toString('base64')) {res.writeHead(401);res.end('{}');return;}
 const url=new URL(req.url,'http://localhost');
 const directory=['GET','HEAD'].includes(req.method) ? url.searchParams.get('directory') || '' : decodeURIComponent(req.headers['x-kilo-directory'] || '');
 if (directory.replaceAll('\\','/')!==process.cwd().replaceAll('\\','/')) {res.writeHead(400);res.end('{}');return;}
 req.url=url.pathname;
 if(req.url==='/session/ses_missing'){res.writeHead(404);res.end(JSON.stringify({message:'Native session not found'}));return;}
 let body='';for await (const chunk of req) body+=chunk;
 if (req.url==='/event') {res.writeHead(200,{'content-type':'text/event-stream'});res.write('data: {}\n\n');subscribers.add(res);res.on('close',()=>subscribers.delete(res));return;}
 const reply=value=>{res.setHeader('content-type','application/json');res.end(JSON.stringify(value));};
 if (req.url==='/session/status') return reply({[session]:{type:currentResponse?'busy':'idle'}});
 if (req.url.endsWith('/abort')) {
   if (process.env.GAMESMITH_FIXTURE_STUCK_ABORT==='1') return;
   if (process.env.GAMESMITH_FIXTURE_STUCK_SETTLE==='1') return reply(true);
   aborted=true;
   const result={info:{error:{name:'MessageAbortedError'}},parts:[]};
   waiting?.(result);waiting=undefined;
   if (currentResponse) {currentResponse.end(JSON.stringify(result));currentResponse=undefined;}
   return reply(true);
 }
 if (req.url.endsWith('/message')) {
   currentResponse=res;
   try {const result=await run(JSON.parse(body).parts[0].text);if (!res.writableEnded) reply(result);}
   catch(error) {if (!res.writableEnded) reply({info:{error:{message:error.message}},parts:[]});}
   finally {if (currentResponse===res) currentResponse=undefined;}
   return;
 }
 reply({id:session});
});
server.listen(0,'127.0.0.1',()=>{if (process.env.GAMESMITH_FIXTURE_STUCK_START!=='1') console.log('kilo server listening on http://127.0.0.1:'+server.address().port);});
