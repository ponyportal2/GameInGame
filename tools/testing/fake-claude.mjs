// Streaming JSON fixture matching installed Claude Code 2.1.317; no provider.
import {createInterface} from 'node:readline';
import {readFileSync,writeFileSync,appendFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
const argv=process.argv.slice(2),value=flag=>argv[argv.indexOf(flag)+1];
writeFileSync('.claude-fixture-argv.json',JSON.stringify(argv));
const session='claude-fixture-session',pending=new Map();let initialized=false,mcp,serial=0;
const emit=r=>process.stdout.write(JSON.stringify({session_id:session,...r})+'\n');
const failure=error=>emit({type:'result',subtype:'error_during_execution',is_error:true,errors:[error]});
async function connect(){
  const spec=JSON.parse(value('--mcp-config')).mcpServers.gamesmith;
  mcp=spawn(spec.command,spec.args,{windowsHide:true,stdio:['pipe','pipe','pipe']});
  createInterface({input:mcp.stdout}).on('line',line=>{const r=JSON.parse(line);pending.get(r.id)?.(r.result);pending.delete(r.id);});
  await request('initialize',{protocolVersion:'2024-11-05'});
  const listed=await request('tools/list',{});
  const tools=listed.tools.map(t=>'mcp__gamesmith__'+t.name);
  if(process.env.GAMESMITH_CLAUDE_EXTRA_TOOL)tools.push('Bash');
  emit({type:'system',subtype:'init',session_id:process.env.GAMESMITH_CLAUDE_DIFFERENT_SESSION?'wrong-session':session,model:'fixture-native-model',tools});initialized=true;
  // Native model latency normally gives the worker time to admit the request.
  // The deterministic fixture instead waits for that actual bridge state.
  const config=JSON.parse(readFileSync(spec.args.at(-1),'utf8')),deadline=Date.now()+5000;
  for(;;){
    if(JSON.parse(readFileSync(join(config.bridge_dir,'operation.json'),'utf8')).active)return;
    if(Date.now()>deadline)throw new Error('Fixture request was not admitted');
    await new Promise(resolve=>setTimeout(resolve,10));
  }
}
function request(method,params){const id=++serial;return new Promise(resolve=>{pending.set(id,resolve);mcp.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');});}
async function tool(name,args={}){
  emit({type:'stream_event',event:{type:'content_block_start',content_block:{type:'tool_use',name:'mcp__gamesmith__'+name}}});
  const result=await request('tools/call',{name,arguments:args});
  if(result.isError)throw new Error(result.content[0].text);
  return JSON.parse(result.content[0].text);
}
async function run(r){
  appendFileSync('.claude-fixture-requests.jsonl',JSON.stringify(r)+'\n');
  if(process.env.GAMESMITH_CLAUDE_STUCK_START==='1')return;
  if(process.env.GAMESMITH_CLAUDE_FAIL_METHOD==='initialize' || process.env.GAMESMITH_CLAUDE_FAIL_METHOD==='session/load'){
    failure('Fixture readiness failure');return;
  }
  if(argv.includes('--resume') && value('--resume')!==session){failure('Native session not found');return;}
  if(process.env.GAMESMITH_CLAUDE_FAIL_METHOD==='session/prompt'){failure('Fixture first prompt failure');return;}
  try{
    if(!initialized)await connect();
    emit({...r,isReplay:true});
    if(process.env.GAMESMITH_CLAUDE_STUCK_TURN==='1' || ['wait','stuck-stop'].includes(r.message.content))return;
    if(r.message.content==='provider-error')throw new Error('Fixture provider error');
    if(r.message.content==='policy'){
      const outside=await request('tools/call',{name:'write',arguments:{path:'../outside.txt',content:'bad'}});
      if(!outside.isError || !/outside|escape/i.test(outside.content[0].text))throw new Error('Expected workspace escape rejection: '+JSON.stringify(outside));
    }
    if(r.message.content==='write')await tool('write',{path:'admitted.txt',content:'first native tool call'});
    if(['reload','test'].includes(r.message.content)){
      await tool('write',{path:'main.gd',content:'extends Node\nvar fixture = true\n'});
      if(r.message.content==='reload')await tool('reload_game');
      else{const test=await tool('start_test_game',{mode:'headless'});await tool('read_test_log',{run_id:test.run_id});await tool('stop_test_game',{run_id:test.run_id});}
    }
    emit({type:'stream_event',event:{type:'message_start',message:{usage:{input_tokens:400}}}});
    emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'thinking_delta',thinking:'Fixture reasoning'}}});
    emit({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'Fixture finished'}}});
    emit({type:'assistant',message:{content:[{type:'text',text:'Fixture finished'}]}});
    emit({type:'stream_event',event:{type:'message_delta',usage:{output_tokens:25}}});
    emit({type:'result',subtype:'success',is_error:false,result:r.message.content==='corrected'?'Corrected completion':'Fixture finished'});
  }catch(error){failure(error.message);}
}
createInterface({input:process.stdin}).on('line',line=>{void run(JSON.parse(line));});
process.stdin.on('end',()=>{mcp?.kill();process.exit();});
