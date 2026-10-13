import {createInterface} from 'node:readline';
import {readFileSync,appendFileSync,writeFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
if(process.argv.includes('status')){console.log(JSON.stringify({isAuthenticated:process.env.GAMESMITH_KIRO_LOGGED_OUT!=='1'}));process.exit();}
writeFileSync('.kiro-fixture-argv.json',JSON.stringify(process.argv.slice(2)));
const emit=r=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',...r})+'\n');
const session='kiro-fixture-session',pending=new Map();let serial=0,active,cancelled=false,mcp;
function clientRequest(method,params){const id='client-'+ ++serial;const promise=new Promise(resolve=>pending.set(id,resolve));emit({id,method,params});return promise;}
function update(u){emit({method:'session/update',params:{sessionId:session,update:u}});}
async function tool(name,args={}) {
  const toolCall={toolCallId:'tool-'+serial,title:'Running: @gamesmith/'+name,kind:name==='write'?'edit':name==='read'?'read':'other',rawInput:args};
  update({sessionUpdate:'tool_call',...toolCall,_meta:{kiro:{mcpServerName:'gamesmith',toolName:name}}});

  const permission=await clientRequest('session/request_permission',{sessionId:session,toolCall,_meta:{mcpToolIdentity:{serverName:'gamesmith',toolName:name}},options:[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}]});
  if(permission.outcome.optionId!=='yes')throw new Error('Permission was denied');
  const result=await mcp.request('tools/call',{name,arguments:args});
  update({sessionUpdate:'tool_call_update',toolCallId:toolCall.toolCallId,status:result.isError?'failed':'completed'});
  if(result.isError)throw new Error(result.content[0].text);
  const data=JSON.parse(result.content[0].text);if(data.ok===false)throw new Error(data.error);return data;
}
async function connectMcp(server){
  const child=spawn(server.command,server.args,{windowsHide:true,stdio:['pipe','pipe','pipe']});
  const requests=new Map();let number=0;
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);if(requests.has(r.id)){requests.get(r.id)(r.result);requests.delete(r.id);}});
  mcp={child,request(method,params){const id=++number;const promise=new Promise(resolve=>requests.set(id,resolve));child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');return promise;}};
  await mcp.request('initialize',{protocolVersion:'2024-11-05'});
  const listed=await mcp.request('tools/list',{});if(!listed.tools.some(t=>t.name==='write'))throw new Error('Missing bounded tools');
}
async function run(r){
  try {
    const message=r.params.prompt.at(-1).text.split('Player request:\n').at(-1);
    update({sessionUpdate:'agent_thought_chunk',content:{type:'text',text:'Fixture reasoning'}});
    if(message==='wait' || message==='stuck-stop')return;
    if(message==='provider-error')throw new Error('Fixture provider error');
    if(message==='policy'){
      const denied=await clientRequest('session/request_permission',{sessionId:session,toolCall:{title:'execute_command: echo bad'},options:[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}]});
      if(denied.outcome.optionId!=='no')throw new Error('Native shell was allowed');
      for(const [index,extra] of [{},{name:'run_commands'},{kind:'execute'}].entries()){
        const toolCall={toolCallId:'spoof-'+serial+'-'+index,title:'gamesmith__write',kind:'other',status:'pending',rawInput:{},...extra};
        if(index)update({sessionUpdate:'tool_call',...toolCall,kind:'execute'});
        const denied=await clientRequest('session/request_permission',{sessionId:session,toolCall,_meta:{mcpToolIdentity:{serverName:'gamesmith',toolName:'write'}},options:[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}]});
        if(denied.outcome.optionId!=='no')throw new Error('Spoofed MCP permission was allowed');
      }
      const reload=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:'unannounced-reload',title:'gamesmith__reload_game',kind:'other',status:'pending',rawInput:{}},options:[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}]});
      if(reload.outcome.optionId!=='no')throw new Error('Unannounced reload reached approval');
      const result=await mcp.request('tools/call',{name:'write',arguments:{path:'../outside.txt',content:'bad'}});if(!result.isError)throw new Error('Workspace escape accepted');
    }
    if(message==='reload' || message==='test'){
      await tool('write',{path:'main.gd',content:'extends Node\nvar fixture = true\n'});
      if(message==='reload')await tool('reload_game');
      else{const test=await tool('start_test_game',{mode:'headless'});await tool('read_test_log',{run_id:test.run_id});await tool('stop_test_game',{run_id:test.run_id});}
    }
    if(cancelled)return;
    update({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'Fixture finished'}});
    emit({id:r.id,result:{stopReason:'end_turn'}});emit({method:'_kiro.dev/metadata',params:{sessionId:session,contextUsagePercentage:12.5,meteringUsage:[{value:9999}]}});active=undefined;
  }catch(error){if(!cancelled){emit({id:r.id,error:{code:-32000,message:error.message}});active=undefined;}}
}
createInterface({input:process.stdin}).on('line',async line=>{
  const r=JSON.parse(line);
  if(!r.method){pending.get(r.id)?.(r.result);pending.delete(r.id);return;}
  appendFileSync('.kiro-fixture-requests.jsonl',JSON.stringify(r)+'\n');
  const reply=result=>emit({id:r.id,result});
  if(r.method===process.env.GAMESMITH_KIRO_FAIL_METHOD){emit({id:r.id,error:{code:-32000,message:'Fixture readiness failure: '+r.method}});return;}
  if(r.method==='initialize'){
    if(process.env.GAMESMITH_KIRO_EXPECT_API_KEY && process.env.KIRO_API_KEY!==process.env.GAMESMITH_KIRO_EXPECT_API_KEY){emit({id:r.id,error:{code:-32000,message:'Native provider key was not inherited'}});return;}
    if(process.env.GAMESMITH_KIRO_STUCK_START==='1')return;reply({protocolVersion:1,agentCapabilities:{loadSession:true},agentInfo:{name:process.env.GAMESMITH_KIRO_WRONG_AGENT?'Other CLI':'Kiro CLI Agent'}});return;
  }
  if(r.method==='session/new' || r.method==='session/load'){
    if(r.method==='session/load' && r.params.sessionId!==session){emit({id:r.id,error:{code:-32000,message:'Native session not found'}});return;}
    const profile=JSON.parse(readFileSync('.kiro/agents/gamesmith.json','utf8'));
    if(r.method==='session/load' && !r.params._meta?.['_kiro.dev/session_file'])throw new Error('Missing explicit native session file');
    await connectMcp(profile.mcpServers.gamesmith);reply({sessionId:process.env.GAMESMITH_KIRO_DIFFERENT_SESSION?'unexpected-session':r.method==='session/load' && process.env.GAMESMITH_KIRO_LOAD_NO_ID?undefined:session,modes:{currentModeId:process.env.GAMESMITH_KIRO_WRONG_MODE?'kiro_default':'gamesmith'},models:{currentModelId:'fixture-native-model'}});return;
  }
  if(r.method==='authenticate'){reply({});return;}
  if(r.method==='session/set_model')throw new Error('Host must not select Kiro model');
  if(r.method==='session/prompt'){if(process.env.GAMESMITH_KIRO_STUCK_TURN==='1')return;active=r;cancelled=false;void run(r);return;}
  if(r.method==='session/cancel'){
    if(process.env.GAMESMITH_KIRO_STUCK_CANCEL==='1')return;
    cancelled=true;if(active){emit({id:active.id,result:{stopReason:'cancelled'}});active=undefined;}return;
  }
});
process.stdin.on('end',()=>{mcp?.child.kill();process.exit();});
