import http from 'node:http';
import {readFileSync,writeFileSync,appendFileSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';

const host=process.argv[process.argv.indexOf('--host')+1],port=Number(new URL(host).port),subscribers=new Set();
let policy,workspace,data,mcp,operation,serial=0,statePolls=0;
const requests=new Map(),permissions=new Map(),sessions=new Map();
const emit=(type,payload)=>{for(const response of subscribers)response.write('data: '+JSON.stringify({type,payload:{type:'updated',payload}})+'\n\n');};
const snapshot=(id,text,parts=[])=>emit('message',{id,session_id:operation.session_id,role:'assistant',parts:[{type:'text',data:{text}},...parts]});
function mcpRequest(method,params){const id=++serial;const promise=new Promise(resolve=>requests.set(id,resolve));mcp.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');return promise;}
async function connectMcp(){
  const cfg=policy.mcp.gamesmith;mcp=spawn(cfg.command,cfg.args,{windowsHide:true,stdio:['pipe','pipe','pipe']});
  createInterface({input:mcp.stdout}).on('line',line=>{const record=JSON.parse(line);if(requests.has(record.id)){requests.get(record.id)(record.result);requests.delete(record.id);}});
  mcp.stderr.pipe(process.stderr);
  await mcpRequest('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'fixture',version:'1'}});
  const result=await mcpRequest('tools/call',{name:'write',arguments:{path:'idle-write.txt',content:'bad'}});if(!result.isError)throw new Error('Inactive MCP was allowed');
}
async function tool(name,args={}){
  const id='tool-'+ ++serial;snapshot('assistant-'+operation.run_id,'',[{type:'tool_call',data:{id,name:'mcp_gamesmith_'+name,input:JSON.stringify(args),finished:true}}]);
  const result=await mcpRequest('tools/call',{name,arguments:args,_meta:{progressToken:id}});
  if(result.isError)throw new Error(result.content[0].text);
  const value=JSON.parse(result.content[0].text);if(value.ok===false)throw new Error(value.error);return value;
}
function permission(tool_name,title){const id=randomUUID(),promise=new Promise(resolve=>permissions.set(id,resolve));emit('permission_request',{id,session_id:operation.session_id,tool_call_id:id,tool_name,description:title,action:'execute',params:{},path:workspace});return promise;}
function complete(result={}){if(!operation)return;const op=operation;operation=undefined;emit('run_complete',{session_id:op.session_id,run_id:op.run_id,message_id:'assistant-'+op.run_id,text:'Fixture finished',...result});}
async function run(op){
  try{
    snapshot('assistant-'+op.run_id,'',[{type:'reasoning',data:{thinking:'Fixture reasoning'}}]);
    if(process.env.GAMESMITH_CRUSH_STUCK_TURN==='1' || op.prompt==='wait')return;
    if(op.prompt==='provider-error')throw new Error('Fixture provider error');
    if(op.prompt==='policy'){
      for(const name of ['bash','write','mcp_external_write','mcp_gamesmith_write'])if(await permission(name,'mcp_gamesmith_write: displayed allowed-looking title')!=='deny')throw new Error('Native permission was allowed');
      for(const args of [{path:'../outside.txt',content:'bad'},{path:'.git/config',content:'bad'}]){const result=await mcpRequest('tools/call',{name:'write',arguments:args});if(!result.isError)throw new Error('Workspace escape was allowed');}
    }
    if(op.prompt==='reload' || op.prompt==='test'){
      await tool('write',{path:'main.gd',content:'extends Node\nvar fixture = true\n'});
      if(op.prompt==='reload')await tool('reload_game');else{const test=await tool('start_test_game',{mode:'headless'});await tool('read_test_log',{run_id:test.run_id});await tool('stop_test_game',{run_id:test.run_id});}
    }
    if(op.prompt==='lost-stream'){for(const response of subscribers)response.end();return;}
    if(operation!==op)return;
    if(op.prompt==='partial-stream'){
      snapshot('assistant-'+op.run_id,'I changed the player');
      emit('run_complete',{session_id:op.session_id,run_id:'stale-run',message_id:'stale',text:'Wrong'});
      complete({text:'I changed the player movement and fixed collisions.'});return;
    }
    snapshot('assistant-'+op.run_id,'Fixture finished');complete();
  }catch(error){if(operation===op)complete({text:'',error:error.message});}
}
const server=http.createServer(async(req,res)=>{
  const pathname=new URL(req.url,'http://localhost').pathname;
  let body='';for await(const chunk of req)body+=chunk;const params=body?JSON.parse(body):{};
  appendFileSync('.crush-fixture-requests.jsonl',JSON.stringify({path:pathname,method:req.method,params})+'\n');
  const reply=(value,status=200)=>{res.writeHead(status,{'content-type':'application/json'});res.end(value===undefined?'':JSON.stringify(value));};
  try{
    const phase=pathname.endsWith('/agent/init')?'agent/init':pathname.includes('/sessions/') && !pathname.endsWith('/messages')?'sessions/load':pathname;
    if(phase===process.env.GAMESMITH_CRUSH_FAIL_METHOD)return reply({message:'Fixture readiness failure: '+phase},500);
    if(pathname==='/v1/health')return reply({status:'ok'});
    if(pathname==='/v1/version')return reply({version:process.env.GAMESMITH_CRUSH_WRONG_VERSION?'99.0.0':'v0.98.1'});
    if(pathname==='/v1/config')return reply({mcp:{external:{type:'stdio',command:'bad'}}});
    if(pathname==='/v1/workspaces' && req.method==='POST'){
      if(params.yolo!==false)throw new Error('YOLO must be disabled');
      if(process.env.GAMESMITH_CRUSH_EXPECT_CONFIG && process.env.CRUSH_GLOBAL_CONFIG!==process.env.GAMESMITH_CRUSH_EXPECT_CONFIG)throw new Error('Native custom config was not inherited');
      if(process.env.GAMESMITH_CRUSH_EXPECT_KEY && process.env.OPENROUTER_API_KEY!==process.env.GAMESMITH_CRUSH_EXPECT_KEY)throw new Error('Native API key was not inherited');
      workspace=params.path;data=params.data_dir;policy=JSON.parse(readFileSync(join(data,'crush.json')));
      if(policy.models || policy.providers || policy.options.disable_auto_summarize!==undefined || policy.options.request_timeout!==undefined)throw new Error('Model/provider/compaction must stay native-owned');
      if(policy.mcp.external?.disabled!==true || !policy.options.disabled_tools.includes('bash') || policy.mcp.gamesmith.timeout<120)throw new Error('Missing MCP/permission restrictions');
      if(policy.permissions.allowed_tools.some(t=>!t.startsWith('mcp_gamesmith_')))throw new Error('Native auto-approval was allowed');
      if(existsSync(join(data,'fixture-sessions.json')))for(const session of JSON.parse(readFileSync(join(data,'fixture-sessions.json'))))sessions.set(session.id,session);
      if(process.env.GAMESMITH_CRUSH_MERGED_MCP_ARGS)policy.mcp.gamesmith.args.unshift('inherited-unrelated-script.mjs');
      return reply({id:'workspace',config:process.env.GAMESMITH_CRUSH_WRONG_POLICY?{...policy,options:{...policy.options,disabled_tools:[]}}:policy,yolo:false});
    }
    if(pathname.endsWith('/events')){res.writeHead(200,{'content-type':'text/event-stream'});res.write(': ready\n\n');subscribers.add(res);res.on('close',()=>subscribers.delete(res));return;}
    if(pathname.endsWith('/sessions') && req.method==='POST'){
      const session={id:randomUUID(),title:params.title,messages:[]};sessions.set(session.id,session);writeFileSync(join(data,'fixture-sessions.json'),JSON.stringify([...sessions.values()]));return reply(session);
    }
    if(pathname.endsWith('/agent/init')){await connectMcp();return reply();}
    if(pathname.endsWith('/mcp/states')){statePolls++;return reply({gamesmith:{name:'gamesmith',state:process.env.GAMESMITH_CRUSH_DELAY_MCP==='1' && statePolls<3?'starting':'connected',tool_count:policy.mcp.gamesmith.enabled_tools.length}});}
    if(pathname.endsWith('/agent/update') && process.env.GAMESMITH_CRUSH_DELAY_MCP==='1' && statePolls<3)throw new Error('Agent updated before MCP tools were connected');
    if(pathname.endsWith('/agent/update'))return reply();
    if(pathname.endsWith('/agent') && req.method==='GET')return reply({is_ready:true,model_cfg:{model:'fixture-native-model',provider:'fixture',reasoning_effort:'high'}});
    if(pathname.endsWith('/agent') && req.method==='POST'){
      if(process.env.GAMESMITH_CRUSH_FAIL_METHOD==='agent/prompt' || params.prompt==='reject-before-admission')return reply({message:'Fixture prompt failure'},500);
      if(!sessions.has(params.session_id))return reply({message:'Native session not found'},404);
      operation=params;reply(undefined,202);setImmediate(()=>void run(params));return;
    }
    if(pathname.endsWith('/cancel')){if(process.env.GAMESMITH_CRUSH_STUCK_CANCEL==='1')return;complete({cancelled:true,text:''});return reply();}
    if(pathname.endsWith('/permissions/grant')){permissions.get(params.permission.id)?.(params.action);permissions.delete(params.permission.id);return reply({resolved:true});}
    const match=pathname.match(/\/sessions\/([^/]+)(\/messages)?$/);
    if(match){const session=sessions.get(decodeURIComponent(match[1]));return session?reply(match[2]?session.messages:session):reply({message:'Native session not found'},404);}
    reply({message:'Unsupported fixture route: '+pathname},404);
  }catch(error){reply({message:error.message},500);}
});
writeFileSync('.crush-fixture-argv.json',JSON.stringify(process.argv.slice(2)));
if(process.env.GAMESMITH_CRUSH_STUCK_START==='1')setInterval(()=>{},1000);else server.listen(port,'127.0.0.1');
