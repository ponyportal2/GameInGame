import {createInterface} from 'node:readline';
import {readFileSync,writeFileSync,appendFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
const args=process.argv.slice(2),session='agy-fixture-session';
writeFileSync('.agy-fixture-argv.json',JSON.stringify(args));
const resumed=args.includes('--conversation') ? args[args.indexOf('--conversation')+1] : '';
const agent=readFileSync('.agents/agents/gamesmith.md','utf8');
const field=name=>JSON.parse(agent.split('\n').find(l=>l.startsWith(name+': ')).slice(name.length+2));
const server=field('mcpServers')[0];
const config=JSON.parse(readFileSync(server.args[1],'utf8'));
const emit=r=>process.stdout.write(JSON.stringify(r)+'\n');
let init=false,mcp,serial=0;
async function connect(){
  const child=spawn(server.command,server.args,{windowsHide:true,stdio:['pipe','pipe','pipe']}),pending=new Map();
  child.stderr.pipe(process.stderr);
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);pending.get(r.id)?.(r);pending.delete(r.id);});
  mcp={child,request(method,params){const id=++serial,promise=new Promise(resolve=>pending.set(id,resolve));child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');return promise;}};
  await mcp.request('initialize',{protocolVersion:'2025-11-25'});await mcp.request('tools/list',{});
}
async function tool(name,arguments_={}){
  const r=await mcp.request('tools/call',{name,arguments:arguments_});
  if(r.result.isError)throw new Error(r.result.content[0].text);
  return JSON.parse(r.result.content[0].text);
}
createInterface({input:process.stdin}).on('line',async line=>{
  const r=JSON.parse(line);appendFileSync('.agy-fixture-requests.jsonl',JSON.stringify(r)+'\n');
  if(process.env.GAMESMITH_AGY_STUCK_START==='1')return;
  if(process.env.GAMESMITH_AGY_EXIT_BEFORE_INIT==='1' || r.message.content.split('Player request:\n').at(-1)==='exit-before-init')process.exit(3);
  if(resumed && resumed!==session){process.stderr.write('Native conversation not found\n');process.exit(3);}
  if(!init){init=true;emit({event:'init',conversation_id:process.env.GAMESMITH_AGY_WRONG_SESSION ? 'wrong-session' : session,init:{agent:'gamesmith'}});await connect();}
  const message=r.message.content.split('Player request:\n').at(-1);
  if(message==='wait' || process.env.GAMESMITH_AGY_STUCK_TURN==='1')return;
  try {
    if(message==='provider-error')throw new Error('Fixture provider error');
    if(message==='policy'){
      const outside=await mcp.request('tools/call',{name:'write',arguments:{path:'../outside.txt',content:'bad'}});
      if(!outside.result.isError)throw new Error('Workspace escape accepted');
    }
    if(message==='reload' || message==='test'){
      await tool('write',{path:'main.gd',content:'extends Node\nvar fixture = true\n'});
      if(message==='reload')await tool('reload_game');
      else{const test=await tool('start_test_game',{mode:'headless'});await tool('read_test_log',{run_id:test.run_id});await tool('stop_test_game',{run_id:test.run_id});}
    }
    emit({event:'step_update',step_update:{conversation_id:session,step_index:1,state:'ACTIVE',step_type:'agent_response',text_delta:'Fixture'}});
    emit({event:'result',result:{conversation_id:session,status:'SUCCESS',response:'Fixture finished',usage:{total_tokens:999999}}});
  }catch(error){emit({event:'result',result:{conversation_id:session,status:'ERROR',response:'',error:error.message}});}
});
process.stdin.on('end',()=>{mcp?.child.kill();process.exit();});
