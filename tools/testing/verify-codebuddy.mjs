// Installed CLI acceptance with a deterministic localhost provider; no paid calls.
import {createServer} from 'node:http';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,unlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createInterface} from 'node:readline';
import {spawn,spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from './assembled-runtime.mjs';
import {killProcessTree} from '../agent/process-tree.mjs';

const root=mkdtempSync(join(tmpdir(),'gs-codebuddy-acceptance-'));
assembleHarnessRuntime('codebuddy',root);
mkdirSync(join(root,'bridge'));
const config={session_file:join(root,'session.json'),workspace:root,bridge_dir:join(root,'bridge'),prompt_path:join(root,'prompt.md'),mcp:join(root,'mcp.mjs'),config_path:join(root,'runtime.json')};
const instructions='Use only GameSmith tools. GameSmith acceptance instruction marker.';
writeFileSync(config.prompt_path,instructions);
const {toolSpecs}=await import(pathToFileURL(join(root,'workspace-tools.mjs')));
const {resolveExecutable}=await import(pathToFileURL(join(root,'server.mjs')));
const executable=resolveExecutable();
const version=spawnSync(executable.bin,[...executable.prefix,'--version'],{encoding:'utf8',windowsHide:true,timeout:15000});
assert.equal(version.status,0,'Installed CLI version probe succeeds');
// Isolated user settings deliberately enable real command hooks. The control
// removes only our CLI hook override, proving the hooks would otherwise run.
const nativeConfig=join(root,'user-config'),hookMarker=join(root,'hook-events.txt'),hookScript=join(root,'sentinel-hook.cjs');
mkdirSync(nativeConfig);
writeFileSync(hookScript,"require('fs').appendFileSync("+JSON.stringify(hookMarker)+",process.argv[2]+'\\n');");
const userSettings=JSON.stringify({disableAllHooks:false,hooks:Object.fromEntries(['PreToolUse','PostToolUse'].map(event=>[event,[{matcher:'mcp__gamesmith__.*',hooks:[{type:'command',command:'"'+process.execPath+'" "'+hookScript+'" '+event}]}]]))});
writeFileSync(join(nativeConfig,'settings.json'),userSettings);
const controlLauncher=join(root,'hook-control.mjs');
writeFileSync(controlLauncher,`import {spawn} from 'node:child_process';
const args=process.argv.slice(2),at=args.indexOf('--settings');
if(at!==-1)args.splice(at,2);
const child=spawn(${JSON.stringify(executable.bin)},[...${JSON.stringify(executable.prefix)},...args],{stdio:'inherit',windowsHide:true});
child.on('error',()=>process.exit(1));child.on('exit',code=>process.exit(code??1));
`);
const allowed=toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10)).sort();
let mainCalls=0,outsideDenied=false,readback=false,child,records=[];
const errors=[];
const http=createServer(async(req,res)=>{
  try {
    let text='';for await(const chunk of req)text+=chunk;
    const body=JSON.parse(text);
    const system=JSON.stringify(body.messages[0]?.content);
    const title=system.includes('sentence-case title');
    const summary=system.includes('You are a conversation summarizer.');
    let deltas,finish='stop';
    if(title || summary){assert.equal((body.tools||[]).length,0);deltas=[{content:summary?'{}':'GameSmith acceptance'}];}
    else {
      assert.equal(body.model,'deepseek-v4.1-flash','Native model selection survives the hook override');
      const systemInstructions=body.messages.filter(m=>m.role==='system').map(m=>JSON.stringify(m.content)).join('\n');
      assert.equal(systemInstructions.split(instructions).length-1,1,'GameSmith instructions appear once in system content');
      for(const message of body.messages.filter(m=>m.role==='user'))assert(!JSON.stringify(message.content).includes(instructions),'GameSmith instructions are absent from user history, including resume');
      assert.deepEqual((body.tools||[]).map(t=>t.function?.name||t.name).sort(),allowed,'Only the complete GameSmith surface reaches inference (stage '+mainCalls+', system '+JSON.stringify(body.messages[0]?.content).slice(0,240)+')');
      mainCalls++;
      if(mainCalls===3)outsideDenied=/outside|escape/i.test(JSON.stringify(body.messages));
      if(mainCalls===4)readback=JSON.stringify(body.messages).includes('native-codebuddy');
      // Deliberately stall the third turn until native Stop closes the stream.
      if(mainCalls===6){res.setHeader('content-type','text/event-stream');res.flushHeaders();return;}
      const tool=mainCalls===1?['write',{path:'native.txt',content:'native-codebuddy'}]:mainCalls===2?['read',{path:'../outside-sentinel.txt'}]:mainCalls===3?['read',{path:'native.txt'}]:null;
      if(tool){deltas=[{tool_calls:[{index:0,id:'native-call-'+mainCalls,type:'function',function:{name:'mcp__gamesmith__'+tool[0],arguments:JSON.stringify(tool[1])}}]}];finish='tool_calls';}
      else deltas=[{content:'CODEBUDDY_ACCEPTED'}];
    }
    res.setHeader('content-type','text/event-stream');
    for(const delta of [{role:'assistant',content:''},...deltas,{}])res.write('data: '+JSON.stringify({id:'fixture',object:'chat.completion.chunk',choices:[{index:0,delta,finish_reason:Object.keys(delta).length?null:finish}]})+'\n\n');
    res.end('data: [DONE]\n\n');
  }catch(error){errors.push(error);res.statusCode=500;res.end('Acceptance assertion failed');}
});
await new Promise(resolve=>http.listen(0,'127.0.0.1',resolve));
// These overrides belong only to the acceptance subprocess, never production settings.
const env={...process.env,CODEBUDDY_CONFIG_DIR:nativeConfig,CODEBUDDY_BASE_URL:'http://127.0.0.1:'+http.address().port,CODEBUDDY_API_KEY:'fixture',CODEBUDDY_MODEL:'deepseek-v4.1-flash'};
function launch(session,control=false){
  records=[];
  writeFileSync(config.config_path,JSON.stringify({...config,session}));
  child=spawn(process.execPath,[join(root,'worker.mjs'),config.config_path],{env:control?{...env,GAMESMITH_CODEBUDDY_BIN:controlLauncher}:env,windowsHide:true,stdio:['pipe','pipe','pipe']});
  child.stderr.on('data',()=>{});
  createInterface({input:child.stdout}).on('line',line=>records.push(JSON.parse(line)));
}
async function until(predicate){
  const deadline=Date.now()+45000;
  for(;;){
    if(errors.length)throw errors[0];
    const found=records.find(predicate);if(found)return found;
    if(Date.now()>deadline)throw new Error('CodeBuddy acceptance timed out: '+JSON.stringify(records.slice(-3)));
    await new Promise(resolve=>setTimeout(resolve,25));
  }
}
function send(record){child.stdin.write(JSON.stringify(record)+'\n');}
async function stop(){
  if(!child)return;
  const previous=child;child=undefined;
  if(previous.exitCode!==null)return;
  const exited=new Promise(resolve=>previous.once('exit',resolve));
  const timeout=setTimeout(()=>killProcessTree(previous.pid),5000);
  previous.stdin.end();await exited;clearTimeout(timeout);
}
try {
  launch(undefined,true);send({type:'prompt',id:'control',message:'Test workspace tools'});
  assert((await until(r=>r.type==='complete')).ok);
  assert(existsSync(hookMarker),'Positive control executes inherited hooks');
  const hookEvents=readFileSync(hookMarker,'utf8').trim().split(/\r?\n/);
  for(const event of ['PreToolUse','PostToolUse'])assert(hookEvents.includes(event),'Positive control executes '+event);
  await stop();unlinkSync(hookMarker);mainCalls=0;outsideDenied=false;readback=false;
  launch();send({type:'prompt',id:'one',message:'Test workspace tools'});
  assert((await until(r=>r.type==='complete')).ok);
  assert.equal(readFileSync(join(root,'native.txt'),'utf8'),'native-codebuddy');
  assert(outsideDenied,'Native MCP rejects escaping the workspace');
  assert(readback,'Native MCP reads the actual edited file');
  const saved=JSON.parse(readFileSync(config.session_file)).session;
  await stop();launch(saved);send({type:'prompt',id:'two',message:'Continue the same conversation'});
  assert((await until(r=>r.type==='complete')).ok);
  assert.equal(JSON.parse(readFileSync(config.session_file)).session,saved);
  assert.equal(mainCalls,5,'Resume does not replay completed tools');
  send({type:'prompt',id:'three',message:'Wait for cancellation'});
  await until(()=>mainCalls===6);
  send({type:'cancel',id:'stop'});
  assert((await until(r=>r.id==='stop')).success,'Native cancellation settles the pending prompt');
  await stop();launch(saved);send({type:'prompt',id:'four',message:'Continue after Stop'});
  assert((await until(r=>r.type==='complete')).ok);
  assert.equal(JSON.parse(readFileSync(config.session_file)).session,saved);
  assert(!existsSync(hookMarker),'Subprocess override suppresses inherited hooks through tools, resume and Stop');
  assert.equal(readFileSync(join(nativeConfig,'settings.json'),'utf8'),userSettings,'Native user settings remain unchanged');
  console.log('PASS installed CodeBuddy '+version.stdout.trim()+': system-only instructions, inherited-hook positive control/suppression, exact MCP surface, write/read, outside denial, resume, Stop and continuation. Artifacts: '+root);
}finally{await stop();http.closeAllConnections();http.close();}
