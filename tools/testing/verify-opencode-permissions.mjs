// Real OpenCode CLI + a deterministic localhost provider. No provider account,
// global configuration changes, or model allowance is used by this acceptance.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawn,spawnSync} from 'node:child_process';
import {createInterface} from 'node:readline';
import {once} from 'node:events';
import {assembleHarnessRuntime} from './assembled-runtime.mjs';
import {killProcessTree} from '../agent/process-tree.mjs';

const directory=mkdtempSync(join(tmpdir(),'gamesmith-opencode-permissions-'));
console.log('Artifacts: '+directory);
const workspace=join(directory,'game'),outside=join(directory,'outside'),data=join(directory,'data');
for(const path of [workspace,outside,data,join(workspace,'.git'),join(workspace,'nested/.git')])mkdirSync(path,{recursive:true});
assert.equal(spawnSync('git',['init','-q'],{cwd:workspace,windowsHide:true}).status,0);
writeFileSync(join(workspace,'allowed.txt'),'inside sentinel');
writeFileSync(join(outside,'secret.txt'),'outside sentinel');
writeFileSync(join(workspace,'.git/description'),'metadata sentinel');
writeFileSync(join(workspace,'nested/.git/config'),'nested metadata sentinel');
symlinkSync(outside,join(workspace,'escape'),process.platform==='win32'?'junction':'dir');
symlinkSync(join(workspace,'nested/.git'),join(workspace,'metadata-alias'),process.platform==='win32'?'junction':'dir');
const runtime=assembleHarnessRuntime('opencode',join(directory,'runtime'));
const {OpenCodeAcpServer,resolveExecutable}=await import(pathToFileURL(join(runtime,'server.mjs')));
const {buildConfig}=await import(pathToFileURL(join(runtime,'protocol.mjs')));
const executable=resolveExecutable();
const version=spawnSync(executable.bin,[...executable.prefix,'--version'],{encoding:'utf8',windowsHide:true});
assert.equal(version.status,0,version.stderr);
console.log('Native OpenCode: '+version.stdout.trim());
assert.match(version.stdout,/2\.1\.2/,'acceptance targets the supported native version');
let proposed,requestCount=0;
const requests=[];
const provider=createServer(async(req,res)=>{
 try{
  let body='';for await(const chunk of req)body+=chunk;
  const payload=JSON.parse(body);requests.push(payload);
  const last=payload.messages.at(-1);
  const tool=payload.tools?.length&&last.role==='user'&&proposed;
  const delta=tool?{role:'assistant',tool_calls:[{index:0,id:'call_'+(++requestCount),type:'function',function:{name:proposed.name,arguments:JSON.stringify(proposed.args)}}]}:{role:'assistant',content:'Acceptance complete.'};
  res.writeHead(200,{'Content-Type':'text/event-stream'});
  for(const [value,finish] of [[delta,null],[{},tool?'tool_calls':'stop']])
   res.write('data: '+JSON.stringify({id:'fixture',object:'chat.completion.chunk',model:'fixture',choices:[{index:0,delta:value,finish_reason:finish}]})+'\n\n');
  res.end('data: [DONE]\n\n');
 }catch(error){res.writeHead(500);res.end(error.message);}
});
await new Promise(resolve=>provider.listen(0,'127.0.0.1',resolve));
const config={workspace,prompt_path:join(directory,'instructions.md'),mcp:join(runtime,'mcp.mjs')};
writeFileSync(config.prompt_path,'Use the requested native file tool.');
const inline={...buildConfig(config),model:'fixture/fixture',providers:{fixture:{name:'Local fixture',env:['GAMESMITH_FIXTURE_KEY'],package:'@opencode/ai/providers/openai-compatible',settings:{baseURL:`http://127.0.0.1:${provider.address().port}/v1`},models:{fixture:{name:'Fixture',limit:{context:32000,output:1000}}}}}};
// This acceptance isolates native state, and permits no production credentials.
const env={...process.env,HOME:data,USERPROFILE:data,APPDATA:data,LOCALAPPDATA:data,XDG_CONFIG_HOME:join(data,'config'),XDG_DATA_HOME:join(data,'share'),XDG_CACHE_HOME:join(data,'cache'),XDG_STATE_HOME:join(data,'state'),OPENCODE_CONFIG_CONTENT:JSON.stringify(inline),OPENCODE_DISABLE_FREE_MODELS:'1',GAMESMITH_FIXTURE_KEY:'local-fixture',GAMESMITH_HOST_BRIDGE_DIR:directory};
let server,worker;
const updates=[];
const watchdog=setTimeout(()=>{console.error('FAIL: Native permission acceptance timed out');if(worker)killProcessTree(worker.pid);server?.close();provider.closeAllConnections();provider.close();process.exitCode=1;},90000);
const check=(condition,message)=>{assert.ok(condition,message);console.log('PASS: '+message);};
try{
 server=new OpenCodeAcpServer({workspace,env,onStderr:line=>console.error(line)});
 server.onUpdate(update=>updates.push(update));
 await server.start();
 const session=await server.request('session/new',{cwd:workspace,mcpServers:[]});
 check(session.configOptions.find(option=>option.id==='mode')?.currentValue==='build','native new session uses confined build mode');
 async function attempt(name,args,allowed,label){
  proposed={name,args};const start=updates.length;
  const result=await server.request('session/prompt',{sessionId:session.sessionId,prompt:[{type:'text',text:label}]});
  assert.equal(result.stopReason,'end_turn');
  const outcome=updates.slice(start).findLast(update=>update.sessionUpdate==='tool_call_update'&&['failed','completed'].includes(update.status));
  writeFileSync(join(directory,'last-outcome.json'),JSON.stringify(outcome,null,2));
  assert.equal(outcome?.status,allowed?'completed':'failed',label+': '+JSON.stringify(outcome));
  console.log('PASS: '+label);
  if(!allowed)assert.match(JSON.stringify(outcome.rawOutput),/permission|denied|not allowed|outside/i,'rejection must enforce policy, not merely reject malformed tool arguments');
  return outcome;
 }
 const read=await attempt('read',{path:join(workspace,'allowed.txt')},true,'reads inside workspace');
 assert.match(JSON.stringify(read.content),/inside sentinel/);
 await attempt('write',{path:join(workspace,'created.txt'),content:'created'},true,'writes inside workspace');
 assert.equal(readFileSync(join(workspace,'created.txt'),'utf8'),'created');
 await attempt('edit',{path:join(workspace,'created.txt'),oldString:'created',newString:'edited'},true,'edits inside workspace');
 assert.equal(readFileSync(join(workspace,'created.txt'),'utf8'),'edited');
 for(const [label,path] of [['outside',join(outside,'secret.txt')],['junction escape',join(workspace,'escape/secret.txt')]]){
  await attempt('read',{path},false,'blocks '+label+' read');
  await attempt('write',{path,content:'corrupt'},false,'blocks '+label+' write');
  await attempt('edit',{path,oldString:'outside sentinel',newString:'corrupt'},false,'blocks '+label+' edit');
  await attempt('write',{path:path.replace('secret.txt','new/file.txt'),content:'corrupt'},false,'blocks '+label+' new file');
  await attempt('glob',{path:path.replace(/[\\/]secret.txt$/,''),pattern:'**/*'},false,'blocks '+label+' glob');
  await attempt('grep',{path:path.replace(/[\\/]secret.txt$/,''),pattern:'sentinel'},false,'blocks '+label+' grep');
 }
 const searched=await attempt('grep',{path:workspace,pattern:'outside sentinel'},true,'workspace grep skips external links');
 assert.doesNotMatch(JSON.stringify(searched.rawOutput),/outside sentinel/,'workspace grep must not return external file contents');
 const listed=await attempt('glob',{path:workspace,pattern:'**/secret.txt'},true,'workspace glob skips external links');
 assert.doesNotMatch(JSON.stringify(listed.rawOutput),/secret\.txt/,'workspace glob must not enumerate external files');
 await attempt('write',{path:join(workspace,'metadata-alias/new/config'),content:'corrupt'},false,'blocks new files through a nested metadata alias');
 for(const path of [join(workspace,'.git/description'),'.git/description',join(workspace,'nested/.git/config')]){
  await attempt('write',{path,content:'corrupt'},false,'blocks metadata write '+path);
  await attempt('edit',{path,oldString:path.includes('nested')?'nested metadata sentinel':'metadata sentinel',newString:'corrupt'},false,'blocks metadata edit '+path);
 }
 assert.equal(readFileSync(join(outside,'secret.txt'),'utf8'),'outside sentinel');
 assert.equal(readFileSync(join(workspace,'.git/description'),'utf8'),'metadata sentinel');
 assert.equal(readFileSync(join(workspace,'nested/.git/config'),'utf8'),'nested metadata sentinel');
 const tools=requests.find(request=>request.tools?.length).tools.map(tool=>tool.function.name);
 for(const tool of ['shell','bash','execute','subagent','task','webfetch','question'])check(!tools.includes(tool),'native model cannot see forbidden '+tool);
 // Seed a real native session with a different agent, then resume it through
 // the production assembled worker. The worker must restore confined mode.
 await server.request('session/set_config_option',{sessionId:session.sessionId,configId:'mode',value:'plan'});
 await server.close();server=null;
 const workerConfig={...config,session:session.sessionId,session_file:join(directory,'session.json'),bridge_dir:directory};
 const configPath=join(directory,'worker.json');writeFileSync(configPath,JSON.stringify(workerConfig));
 proposed={name:'write',args:{path:join(workspace,'resumed.txt'),content:'confined resume'}};
 worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{cwd:workspace,env,windowsHide:true,stdio:['pipe','pipe','pipe']});
 const closed=once(worker,'close'),records=[];
 worker.stderr.on('data',chunk=>process.stderr.write(chunk));
 const completion=new Promise((resolve,reject)=>{
  worker.on('error',reject);worker.on('exit',()=>reject(new Error('Worker exited before completion')));
  createInterface({input:worker.stdout}).on('line',line=>{
   const record=JSON.parse(line);records.push(record);
   if(record.type==='complete')resolve(record);
   if(record.type==='response'&&!record.success)reject(new Error(record.error));
  });
 });
 try{
  worker.stdin.write(JSON.stringify({id:'resume',type:'prompt',message:'Write resumed.txt'})+'\n');
  check((await completion).ok,'production worker resumes a native plan session');
  check(readFileSync(join(workspace,'resumed.txt'),'utf8')==='confined resume','resumed worker can perform build-only edit');
 }finally{worker.stdin.end();await closed;worker=null;writeFileSync(join(directory,'worker-records.json'),JSON.stringify(records,null,2));}
 server=new OpenCodeAcpServer({workspace,env});await server.start();
 const resumed=await server.request('session/load',{sessionId:session.sessionId,cwd:workspace,mcpServers:[]});
 check(resumed.configOptions.find(option=>option.id==='mode')?.currentValue==='build','native persisted session confirms worker restored build mode');
 await server.close();server=null;
 // Native plugin load failures are logged, not fatal. Prove our worker refuses
 // prompts even when the native session itself can still be constructed.
 writeFileSync(join(runtime,'server.ts'),"throw new Error('Intentional guard load failure');\n");
 const before=requests.length;
 worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{cwd:workspace,env,windowsHide:true,stdio:['pipe','pipe','pipe']});
 const failedClosed=once(worker,'close');
 worker.stderr.on('data',chunk=>process.stderr.write(chunk));
 const rejected=new Promise((resolve,reject)=>{
  worker.on('error',reject);worker.on('exit',()=>reject(new Error('Worker exited before rejection')));
  createInterface({input:worker.stdout}).on('line',line=>{const record=JSON.parse(line);if(record.type==='response')resolve(record);});
 });
 try {
  worker.stdin.write(JSON.stringify({id:'missing-guard',type:'prompt',message:'Do not run without the guard'})+'\n');
  const response=await rejected;
  check(response.success===false&&response.initialization_failed===true&&/workspace guard was not loaded/.test(response.error),'missing native guard rejects before accepting a prompt');
  check(requests.length===before,'missing guard makes no model requests');
 }finally{worker.stdin.end();await failedClosed;worker=null;}
}finally{
 clearTimeout(watchdog);
 await server?.close();
 provider.closeAllConnections();await new Promise(resolve=>provider.close(resolve));
 writeFileSync(join(directory,'updates.json'),JSON.stringify(updates,null,2));
 writeFileSync(join(directory,'requests.json'),JSON.stringify(requests,null,2));
}
