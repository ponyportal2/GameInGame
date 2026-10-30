import { writeFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { spawn } from 'node:child_process';

const config=JSON.parse(process.env.OPENCODE_CONFIG_CONTENT || '{}');
const permissions=config.agents?.build?.permissions || [];
const allows=action=>permissions.some(rule=>rule.action===action && rule.resource==='*' && rule.effect==='allow');
// The fixture fails loudly when the adapter stops confining the agent, so the
// policy cannot silently regress behind a green lifecycle run.
if (config.default_agent!=='build') throw new Error('Fixture requires the confined build agent');
if (!permissions.some(rule=>rule.action==='*' && rule.resource==='*' && rule.effect==='deny')) throw new Error('Fixture requires the default-deny rule');
for (const action of ['read','write','edit','glob','grep','gamesmith_*']) if (!allows(action)) throw new Error('Fixture requires the '+action+' allow rule');
for (const action of ['shell','execute','subagent','question','webfetch','external_directory','skill']) if (allows(action)) throw new Error('Fixture must not allow '+action);
if (!(config.instructions || []).length) throw new Error('Fixture requires the game instructions');

const sessionId='ses_fixture';
let model='fixture/model', mode='build', serial=0, callSerial=0, cancelled=false, resolveStall=null, cancelSettles=true;

const send=message=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',...message})+'\n');
const update=value=>send({method:'session/update',params:{sessionId,update:value}});
function options() {
  return [
    {id:'model',category:'model',type:'select',currentValue:model,options:[{value:'fixture/model',name:'Fixture model'}]},
    {id:'mode',category:'mode',type:'select',currentValue:mode,options:[{value:'build',name:'Build'},{value:'plan',name:'Plan'}]},
  ];
}
function rpcError(code,message) {const error=new Error(message);error.code=code;return error;}

const mcpConfig=config.mcp?.servers?.gamesmith;
const mcp=mcpConfig ? spawn(mcpConfig.command[0],mcpConfig.command.slice(1),{windowsHide:true,stdio:['pipe','pipe','pipe'],env:process.env}) : null;
await writeFile('.opencode-fixture-pids.json',JSON.stringify({cli:process.pid,mcp:mcp?.pid}));
const pending=new Map();let mcpId=0;
if (mcp) {
  createInterface({input:mcp.stdout}).on('line',line=>{
    const frame=JSON.parse(line);
    if (pending.has(frame.id)) {pending.get(frame.id)(frame);pending.delete(frame.id);}
  });
  mcp.stderr.pipe(process.stderr);
}
function request(method,params) {
  const next=++mcpId;
  const result=new Promise(resolve=>pending.set(next,resolve));
  mcp.stdin.write(JSON.stringify({jsonrpc:'2.0',id:next,method,params})+'\n');
  return result;
}
if (mcp) {
  await request('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'fixture',version:'1'}});
  const listed=await request('tools/list',{});
  if (!listed.result.tools.find(tool=>tool.name==='reload_game')) throw new Error('MCP missing host tools');
}
async function host(name,args={}) {
  const id='call_'+(++callSerial);
  update({sessionUpdate:'tool_call',toolCallId:id,name:'gamesmith_'+name,title:'gamesmith_'+name,kind:'other',status:'in_progress',rawInput:args,locations:[]});
  const frame=await request('tools/call',{name,arguments:args,_meta:{progressToken:id}});
  const failed=frame.result.isError===true;
  update({sessionUpdate:'tool_call_update',toolCallId:id,status:failed ? 'failed' : 'completed',content:frame.result.content,rawOutput:frame.result.content?.[0]?.text,locations:[]});
  return JSON.parse(frame.result.content[0].text);
}
function stall() {return cancelled && cancelSettles ? Promise.resolve() : new Promise(resolve=>{resolveStall=resolve;});}
function cancelTurn() {
  cancelled=true;
  if (!cancelSettles) return;
  resolveStall?.();resolveStall=null;
}
async function run(prompt) {
  cancelled=false;resolveStall=null;
  cancelSettles=process.env.GAMESMITH_FIXTURE_STUCK_ABORT!=='1' && process.env.GAMESMITH_FIXTURE_STUCK_SETTLE!=='1';
  await writeFile('.opencode-fixture-busy.json',JSON.stringify({prompt}));
  if (prompt==='wait') {
    update({sessionUpdate:'agent_thought_chunk',content:{type:'text',text:'Fixture is thinking before completion'}});
    await stall();
    if (cancelled) return {stopReason:'cancelled'};
    return {stopReason:'end_turn'};
  }
  if (prompt==='stuck-abort' || prompt==='settle-stall') {
    await stall();
    return {stopReason:'cancelled'};
  }
  if (prompt==='provider-error') throw rpcError(-32603,'Fixture provider error');
  if (prompt==='incomplete') return {stopReason:'max_tokens'};
  if (prompt==='tool-round-only') return {stopReason:'max_turn_requests'};
  if (prompt==='reload') {
    await writeFile('main.gd','extends Node\n');
    const result=await host('reload_game');
    if (cancelled) return {stopReason:'cancelled'};
    if (!result.ok) throw new Error(result.error);
  }
  if (prompt==='test') {
    await writeFile('main.gd','extends Node\n');
    const result=await host('start_test_game',{mode:'headless'});
    if (!result.ok) throw new Error(result.error);
    const stopped=await host('stop_test_game',{run_id:result.run_id});
    if (stopped.state!=='exited') throw new Error('Test did not exit');
  }
  if (prompt==='repair-reload') {
    await writeFile('main.gd','extends Node\nfunc broken(:\n');
    const failed=await host('reload_game');
    if (failed.ok || !failed.diagnostics) throw new Error('Missing reload diagnostics');
    await writeFile('main.gd','extends Node\nvar repaired = true\n');
    const tested=await host('start_test_game',{mode:'headless'});
    if (!tested.ok) throw new Error(tested.error);
    await host('read_test_log',{run_id:tested.run_id});
    await host('stop_test_game',{run_id:tested.run_id});
    const reloaded=await host('reload_game');
    if (!reloaded.ok) throw new Error(reloaded.error);
  }
  update({sessionUpdate:'agent_message_chunk',messageId:'msg_fixture',content:{type:'text',text:'Fixture finished'}});
  // Context occupancy and per-call consumption are different measurements: a
  // turn that adds 120 tokens to the prompt still leaves the context at 5120.
  if (prompt!=='context-missing') update({sessionUpdate:'usage_update',used:5120,size:200000,cost:{amount:0,currency:'USD'}});
  return {stopReason:'end_turn',usage:{inputTokens:100,outputTokens:20,totalTokens:120}};
}
const handlers={
  initialize:()=>({protocolVersion:1,agentCapabilities:{loadSession:true,promptCapabilities:{embeddedContext:true,image:true}},agentInfo:{name:'fixture',version:'1.0.0'}}),
  'session/new':()=>({sessionId,configOptions:options()}),
  'session/load':params=>{
    if (params.sessionId!==sessionId) throw rpcError(-32602,'Invalid params: session not found: '+params.sessionId);
    return {configOptions:options()};
  },
  'session/set_config_option':params=>{
    if (params.configId==='model') model=params.value;
    if (params.configId==='mode') mode=params.value;
    return {configOptions:options()};
  },
  'session/prompt':params=>run(params.prompt?.[0]?.text || ''),
};
createInterface({input:process.stdin}).on('line',async line=>{
  let message;
  try {message=JSON.parse(line);} catch {return;}
  if (message.method==='session/cancel') {cancelTurn();return;}
  if (message.method==='session/update') return;
  if (message.method==='initialize' && process.env.GAMESMITH_FIXTURE_STUCK_START==='1') return;
  const handler=handlers[message.method];
  if (!handler) {send({id:message.id,error:{code:-32601,message:'Method not found: '+message.method}});return;}
  try {send({id:message.id,result:await handler(message.params || {})});}
  catch(error) {send({id:message.id,error:{code:error.code || -32603,message:error.message}});}
});
