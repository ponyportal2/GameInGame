import {createInterface} from 'node:readline';
import {readFileSync,appendFileSync,writeFileSync} from 'node:fs';
import {spawn} from 'node:child_process';
if(process.argv.includes('status')){console.log(JSON.stringify({isAuthenticated:process.env.GAMESMITH_KIRO_LOGGED_OUT!=='1'}));process.exit();}
writeFileSync('.kiro-fixture-argv.json',JSON.stringify(process.argv.slice(2)));
const emit=r=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',...r})+'\n');
const session='kiro-fixture-session',pending=new Map();let serial=0,active,cancelled=false,mcp,mode='vibe',autopilot='on';
function clientRequest(method,params){const id='client-'+ ++serial;const promise=new Promise(resolve=>pending.set(id,resolve));emit({id,method,params});return promise;}
function update(u){emit({method:'session/update',params:{sessionId:session,update:u}});}
function configOptions(){return [
  {type:'select',id:'mode',name:'Mode',category:'mode',currentValue:mode,options:[{value:'vibe',name:'Default'},{value:'gamesmith',name:'GameSmith game editing'}]},
  {type:'select',id:'model',name:'Model',currentValue:'fixture-native-model',options:[]},
  {type:'select',id:'autopilot',name:'Autopilot',currentValue:autopilot,options:[{value:'on',name:'On'},{value:'off',name:'Off'}]},
];}
const options=[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}];
const identity=(name,server='gamesmith')=>({kiro:{toolId:'mcp_'+server+'_'+name,mcpTool:{version:1,identity:{serverName:server,toolName:name}}}});
async function tool(name,args={}) {
  const toolCall={toolCallId:'tool-'+ ++serial,title:'Running: @gamesmith/'+name,kind:'other',rawInput:{tool_id:'gamesmith::'+name,arguments:args}};
  update({sessionUpdate:'tool_call',...toolCall,_meta:{kiro:{serverName:'gamesmith',toolOrigin:'default'}}});
  const permission=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:toolCall.toolCallId,status:'pending',title:toolCall.title},_meta:identity(name),options});
  if(permission.outcome.optionId!=='yes')throw new Error('Permission was denied');
  const result=await mcp.request('tools/call',{name,arguments:args});
  update({sessionUpdate:'tool_call_update',toolCallId:toolCall.toolCallId,status:result.isError?'failed':'completed',rawInput:toolCall.rawInput,_meta:{kiro:{serverName:'gamesmith',toolOrigin:'default'}}});
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
      const denied=await clientRequest('session/request_permission',{sessionId:session,toolCall:{title:'shell: echo bad'},options});
      if(denied.outcome.optionId!=='no')throw new Error('Native shell was allowed');
      // Announced GameSmith call whose consent lacks the structured identity.
      update({sessionUpdate:'tool_call',toolCallId:'spoof-identity',title:'Running: @gamesmith/write',kind:'other',status:'pending',rawInput:{tool_id:'gamesmith::write',arguments:{}},_meta:{kiro:{serverName:'gamesmith'}}});
      const bare=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:'spoof-identity',title:'@gamesmith/write'},options});
      if(bare.outcome.optionId!=='no')throw new Error('Unidentified MCP consent was allowed');
      // Consent claiming a different MCP server than the announcement.
      update({sessionUpdate:'tool_call',toolCallId:'spoof-server',title:'Running: @gamesmith/write',kind:'other',status:'pending',rawInput:{tool_id:'gamesmith::write',arguments:{}},_meta:{kiro:{serverName:'gamesmith'}}});
      const foreign=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:'spoof-server',title:'@gamesmith/write'},_meta:identity('write','external'),options});
      if(foreign.outcome.optionId!=='no')throw new Error('Foreign MCP identity was allowed');
      // Tool kind changed after the announcement.
      update({sessionUpdate:'tool_call',toolCallId:'spoof-kind',title:'Running: @gamesmith/write',kind:'other',status:'pending',rawInput:{tool_id:'gamesmith::write',arguments:{}},_meta:{kiro:{serverName:'gamesmith'}}});
      update({sessionUpdate:'tool_call_update',toolCallId:'spoof-kind',status:'pending',kind:'execute'});
      const changed=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:'spoof-kind',title:'@gamesmith/write'},_meta:identity('write'),options});
      if(changed.outcome.optionId!=='no')throw new Error('Changed tool kind was allowed');
      const reload=await clientRequest('session/request_permission',{sessionId:session,toolCall:{toolCallId:'unannounced-reload',title:'@gamesmith/reload_game'},_meta:identity('reload_game'),options});
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
    emit({id:r.id,result:{stopReason:'end_turn'}});update({sessionUpdate:'session_info_update',_meta:{kiro:{kind:'context_usage',usagePercentage:12.5}}});active=undefined;
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
    if(process.env.GAMESMITH_KIRO_STUCK_START==='1')return;
    // V3 reports no agentInfo; the extension list identifies the engine.
    reply(process.env.GAMESMITH_KIRO_WRONG_AGENT?{protocolVersion:1,agentCapabilities:{loadSession:true}}:{protocolVersion:1,agentCapabilities:{loadSession:true,promptCapabilities:{image:true,embeddedContext:true},_meta:{kiro:{extensionMethods:[]}}}});return;
  }
  if(r.method==='session/new' || r.method==='session/load'){
    if(r.method==='session/load' && r.params.sessionId!==session){emit({id:r.id,error:{code:-32000,message:'Native session not found'}});return;}
    const profile=JSON.parse(readFileSync('.kiro/agents/gamesmith.json','utf8'));
    if(!Array.isArray(profile.permissions?.rules))throw new Error('Missing universal agent permissions block');
    await connectMcp(profile.mcpServers.gamesmith);
    reply({sessionId:process.env.GAMESMITH_KIRO_DIFFERENT_SESSION?'unexpected-session':r.method==='session/load' && process.env.GAMESMITH_KIRO_LOAD_NO_ID?undefined:session,
      modes:{availableModes:[{id:'vibe',name:'Default'},{id:'gamesmith',name:'GameSmith game editing'}],currentModeId:mode},configOptions:configOptions()});return;
  }
  if(r.method==='session/set_mode'){
    if(!process.env.GAMESMITH_KIRO_WRONG_MODE && r.params.modeId==='gamesmith')mode='gamesmith';
    update({sessionUpdate:'config_option_update',configOptions:configOptions()});reply({});return;
  }
  if(r.method==='session/set_config_option'){
    if(r.params.configId!=='autopilot' || r.params.value!=='off'){emit({id:r.id,error:{code:-32000,message:'Unexpected config option'}});return;}
    if(process.env.GAMESMITH_KIRO_AUTOPILOT_STUCK!=='1')autopilot='off';reply({configOptions:configOptions()});return;
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
