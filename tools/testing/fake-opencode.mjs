import { writeFile, readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const args=process.argv.slice(2);
const prompt=args.at(-1);
const session='ses_fixture';
const emit=frame=>process.stdout.write(JSON.stringify({sessionID:session,...frame})+'\n');
emit({type:'step_start',part:{}});
if (prompt==='provider-error') {emit({type:'error',error:{data:{message:'Fixture provider error'}}});process.exit();}
if (prompt==='incomplete') process.exit();
if (prompt==='tool-round-only') {emit({type:'step_finish',part:{reason:'tool-calls'}});process.exit();}
if (prompt==='follow up' && args[args.indexOf('--session')+1]!==session) throw new Error('Missing explicit native session resume');
const config=JSON.parse(process.env.OPENCODE_CONFIG_CONTENT);
const hooks=await (await import(config.plugin[0])).default({directory:process.cwd()});
const mcp=spawn(config.mcp.gamesmith.command[0],config.mcp.gamesmith.command.slice(1),{windowsHide:true,stdio:['pipe','pipe','pipe'],env:process.env});
await writeFile('.opencode-fixture-pids.json',JSON.stringify({cli:process.pid,mcp:mcp.pid}));
const pending=new Map();let id=0;
createInterface({input:mcp.stdout}).on('line',line=>{
  const frame=JSON.parse(line);
  if (pending.has(frame.id)) {pending.get(frame.id)(frame);pending.delete(frame.id);}
});
mcp.stderr.pipe(process.stderr);
function request(method,params) {
  const next=++id;
  const result=new Promise(resolve=>pending.set(next,resolve));
  mcp.stdin.write(JSON.stringify({jsonrpc:'2.0',id:next,method,params})+'\n');return result;
}
await request('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'fixture',version:'1'}});
const listed=await request('tools/list',{});
if (!listed.result.tools.find(t=>t.name==='reload_game')) throw new Error('MCP missing host tools');
async function host(name,args={}) {
  await hooks['tool.execute.before']({tool:'gamesmith_'+name},{args});
  const frame=await request('tools/call',{name,arguments:args,_meta:{progressToken:String(id+1)}});
  emit({type:'tool_use',part:{tool:'gamesmith_'+name,state:{status:frame.result.isError?'error':'completed'}}});
  return JSON.parse(frame.result.content[0].text);
}
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
const closed=once(mcp,'close');mcp.stdin.end();await closed;
