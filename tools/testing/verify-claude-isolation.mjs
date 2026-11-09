// Opt-in installed Claude CLI acceptance. Local provider + isolated native profile;
// no paid calls and no changes to the user's actual configuration or credentials.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createInterface} from 'node:readline';
import {assembleHarnessRuntime} from './assembled-runtime.mjs';
import {killProcessTree} from '../agent/process-tree.mjs';

const root=mkdtempSync(join(tmpdir(),'gs-claude-isolation-'));
assembleHarnessRuntime('claude',root);
for(const directory of ['profile/agents','game','bridge','native-workspace'])mkdirSync(join(root,directory),{recursive:true});
const config={workspace:join(root,'game'),bridge_dir:join(root,'bridge'),session_file:join(root,'session.json'),prompt_path:join(root,'prompt.md'),mcp:join(root,'mcp.mjs'),config_path:join(root,'runtime.json')};
const instructions='GAMESMITH_SYSTEM_SENTINEL: use only GameSmith tools.';
writeFileSync(config.prompt_path,instructions);
writeFileSync(config.config_path,JSON.stringify(config));
writeFileSync(join(root,'profile','CLAUDE.md'),'USER_MEMORY_SENTINEL: Always prefer purple cats.');
writeFileSync(join(root,'profile','agents','custom-sentinel.md'),'---\nname: custom-sentinel\ndescription: Isolation test agent\nmodel: claude-haiku-4-5-20251001\n---\nUSER_AGENT_SENTINEL: Always prefer orange dogs.\n');
const {launchArgs,resolveExecutable}=await import(pathToFileURL(join(root,'server.mjs')));
const {toolSpecs}=await import(pathToFileURL(join(root,'workspace-tools.mjs')));
const allowed=toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10)).sort();
const executable=resolveExecutable();
const version=spawnSync(executable.bin,[...executable.prefix,'--version'],{encoding:'utf8',windowsHide:true,timeout:15000});
assert.equal(version.status,0,'Installed CLI version probe succeeds');
let phase,requests=[],child,records=[],stderr='';
const http=createServer(async(req,res)=>{
  let text='';for await(const chunk of req)text+=chunk;
  let body;try{body=JSON.parse(text);}catch{res.end('{}');return;}
  if(!req.url.includes('messages') || req.url.includes('count_tokens')){res.setHeader('content-type','application/json');res.end(JSON.stringify({input_tokens:100}));return;}
  // Only dummy fixture credentials are recorded. Actual native credentials are
  // removed from the subprocess environment and never copied into this profile.
  requests.push({phase,body,apiKey:req.headers['x-api-key'],authorization:req.headers.authorization});
  if(phase==='wait'){res.setHeader('content-type','text/event-stream');res.flushHeaders();return;}
  const tool=phase==='fresh' && requests.filter(r=>r.phase===phase).length===1;
  const block=tool?{type:'tool_use',id:'call_isolation',name:'mcp__gamesmith__write',input:{path:'native.txt',content:'isolated-native-write'}}:{type:'text',text:'ISOLATION_ACCEPTED'};
  const message={id:'msg_fixture',type:'message',role:'assistant',model:body.model,content:[block],stop_reason:tool?'tool_use':'end_turn',stop_sequence:null,usage:{input_tokens:100,output_tokens:8}};
  if(!body.stream){res.setHeader('content-type','application/json');res.end(JSON.stringify(message));return;}
  res.setHeader('content-type','text/event-stream');
  const start=tool?{...block,input:{}}:{...block,text:''};
  const delta=tool?{type:'input_json_delta',partial_json:JSON.stringify(block.input)}:{type:'text_delta',text:block.text};
  const events=[['message_start',{type:'message_start',message:{...message,content:[],stop_reason:null}}],['content_block_start',{type:'content_block_start',index:0,content_block:start}],['content_block_delta',{type:'content_block_delta',index:0,delta}],['content_block_stop',{type:'content_block_stop',index:0}],['message_delta',{type:'message_delta',delta:{stop_reason:message.stop_reason,stop_sequence:null},usage:{output_tokens:8}}],['message_stop',{type:'message_stop'}]];
  for(const [event,data] of events)res.write('event: '+event+'\ndata: '+JSON.stringify(data)+'\n\n');res.end();
});
await new Promise(resolve=>http.listen(0,'127.0.0.1',resolve));
const profile=join(root,'profile'),settingsPath=join(profile,'settings.json');
let settings={model:'claude-sonnet-4-6',env:{ANTHROPIC_API_KEY:'isolation-fixture',CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:'1',CLAUDE_CODE_DISABLE_CLAUDE_MDS:'0'}};
const env={...process.env,CLAUDE_CONFIG_DIR:profile,ANTHROPIC_BASE_URL:'http://127.0.0.1:'+http.address().port,CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:'1'};
for(const key of ['ANTHROPIC_MODEL','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','CLAUDE_CODE_SIMPLE','CLAUDE_CODE_SAFE_MODE','CLAUDE_CODE_DISABLE_CLAUDE_MDS','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY'])delete env[key];
function saveSettings(){writeFileSync(settingsPath,JSON.stringify(settings));}
function nativeRecords(stdout){return stdout.trim().split('\n').flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}});}
async function control(name,agent){
  phase=name;settings={...settings,...(agent?{agent:'custom-sentinel'}:{})};saveSettings();
  const args=launchArgs(config),at=args.indexOf('--settings')+1,overrides=JSON.parse(args[at]);
  // Remove only the production isolation overrides for a native positive control.
  delete overrides.agent;delete overrides.env?.CLAUDE_CODE_DISABLE_CLAUDE_MDS;args[at]=JSON.stringify(overrides);
  const native=spawn(executable.bin,[...executable.prefix,...args],{cwd:join(root,'native-workspace'),env,windowsHide:true,stdio:['pipe','pipe','pipe']});
  let stdout='',errors='';native.stdout.on('data',d=>stdout+=d);native.stderr.on('data',d=>errors+=d);
  const timeout=setTimeout(()=>killProcessTree(native.pid),25000);
  native.stdin.end(JSON.stringify({type:'user',message:{role:'user',content:'Reply ISOLATION_ACCEPTED'}})+'\n');
  const code=await new Promise(resolve=>native.on('exit',resolve));clearTimeout(timeout);
  writeFileSync(join(root,name+'.stdout'),stdout);writeFileSync(join(root,name+'.stderr'),errors);
  assert.equal(code,0,'Native positive control completes');
  const init=nativeRecords(stdout).find(r=>r.type==='system'&&r.subtype==='init');
  assert.deepEqual(init?.tools.sort(),allowed,'Positive control exposes exact MCP tools');
  const context=JSON.stringify(requests.filter(r=>r.phase===phase));
  assert(context.includes('USER_MEMORY_SENTINEL'),'Positive control loads global CLAUDE.md');
  assert.equal(context.includes('USER_AGENT_SENTINEL'),agent,'Positive control exercises the user agent setting');
  assert.equal(init.model,agent?'claude-haiku-4-5-20251001':settings.model,'Control observes agent/native model selection');
}
function launch(session){
  records=[];writeFileSync(config.config_path,JSON.stringify({...config,session}));
  child=spawn(process.execPath,[join(root,'worker.mjs'),config.config_path],{env,windowsHide:true,stdio:['pipe','pipe','pipe']});
  child.stderr.on('data',d=>stderr+=d);createInterface({input:child.stdout}).on('line',line=>records.push(JSON.parse(line)));
}
function send(record){child.stdin.write(JSON.stringify(record)+'\n');}
async function until(predicate){
  const deadline=Date.now()+25000;
  for(;;){const result=predicate();if(result)return result;
    if(Date.now()>deadline)throw new Error('Claude isolation timeout: '+JSON.stringify(records.slice(-3))+' '+stderr.slice(-500));
    await new Promise(resolve=>setTimeout(resolve,25));}
}
async function complete(){const result=await until(()=>records.find(r=>r.type==='complete'||(r.type==='response'&&!r.success)));assert(result.ok,result.error);return result;}
async function stop(){
  if(!child)return;const previous=child;child=undefined;
  if(previous.exitCode!==null)return;
  const exited=new Promise(resolve=>previous.once('exit',resolve));
  const timer=setTimeout(()=>killProcessTree(previous.pid),5000);previous.stdin.end();await exited;clearTimeout(timer);
}
function checkRequests(name,oauth=false){
  const captured=requests.filter(r=>r.phase===name);assert(captured.length,'The installed CLI reached the local provider');
  for(const request of captured){
    const context=JSON.stringify(request.body);
    assert(!context.includes('USER_AGENT_SENTINEL'),'Global custom agent instructions are absent');
    assert(!context.includes('USER_MEMORY_SENTINEL'),'Global CLAUDE.md is absent');
    assert(JSON.stringify(request.body.system).includes(instructions),'Explicit GameSmith instructions remain system content');
    assert.equal(request.body.model,settings.model,'Native profile model is preserved');
    assert.deepEqual((request.body.tools||[]).map(t=>t.name).sort(),allowed,'The inference request has only the exact complete GameSmith MCP registry');
    if(oauth)assert.equal(request.authorization,'Bearer sk-ant-oat01-isolation-fixture','Native OAuth credential discovery remains available');
    else assert.equal(request.apiKey,'isolation-fixture','User settings still supply native API authentication');
  }
}
try{
  await control('control-memory',false);await control('control-agent',true);
  const originalSettings=readFileSync(settingsPath,'utf8');
  phase='fresh';launch();send({type:'prompt',id:'fresh',message:'Write native.txt, then reply ISOLATION_ACCEPTED'});await complete();checkRequests(phase);
  assert.equal(readFileSync(join(config.workspace,'native.txt'),'utf8'),'isolated-native-write','Explicit MCP tools actually execute');
  const session=JSON.parse(readFileSync(config.session_file)).session;
  await stop();phase='resume';launch(session);send({type:'prompt',id:'resume',message:'Continue the same session'});await complete();checkRequests(phase);
  assert.equal(JSON.parse(readFileSync(config.session_file)).session,session);
  phase='wait';send({type:'prompt',id:'wait',message:'Wait for Stop'});await until(()=>requests.some(r=>r.phase==='wait'));
  send({type:'cancel',id:'stop'});assert((await until(()=>records.find(r=>r.id==='stop'))).success);await stop();
  phase='after-stop';launch(session);send({type:'prompt',id:'after-stop',message:'Continue after Stop'});await complete();checkRequests(phase);
  assert.equal(JSON.parse(readFileSync(config.session_file)).session,session);await stop();
  assert.equal(readFileSync(settingsPath,'utf8'),originalSettings,'Production never rewrites native user settings');
  // A synthetic credential in a disposable profile tests the native OAuth read
  // path, not subscription validity or access to Anthropic's actual service.
  delete settings.env.ANTHROPIC_API_KEY;saveSettings();
  writeFileSync(join(profile,'.credentials.json'),JSON.stringify({claudeAiOauth:{accessToken:'sk-ant-oat01-isolation-fixture',refreshToken:'fixture',expiresAt:Date.now()+3600000,scopes:['user:inference','user:profile'],subscriptionType:'pro',rateLimitTier:'default_claude_pro'}}));
  phase='oauth-fixture';launch();send({type:'prompt',id:'oauth',message:'Reply ISOLATION_ACCEPTED'});await complete();checkRequests(phase,true);
  console.log('PASS installed '+version.stdout.trim()+': customization positive controls, isolated system/user context, native model/API-key settings, exact MCP execution, resume, Stop and native OAuth credential discovery. Artifacts: '+root);
}finally{
  await stop();writeFileSync(join(root,'requests.json'),JSON.stringify(requests,null,2));writeFileSync(join(root,'records.json'),JSON.stringify(records,null,2));writeFileSync(join(root,'stderr.log'),stderr);http.closeAllConnections();http.close();
  console.log('Claude isolation artifacts: '+root);
}
