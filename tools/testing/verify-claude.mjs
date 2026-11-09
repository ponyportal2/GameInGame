// Explicit installed-CLI / real-provider acceptance. Uses native auth and model.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createInterface} from 'node:readline';
import {assembleHarnessRuntime} from './assembled-runtime.mjs';
import {killProcessTree} from '../agent/process-tree.mjs';
const root=mkdtempSync(join(tmpdir(),'gamesmith-claude-live-'));
mkdirSync(join(root,'bridge'));mkdirSync(join(root,'game'));
assembleHarnessRuntime('claude',root);
const config={workspace:join(root,'game'),bridge_dir:join(root,'bridge'),session_file:join(root,'session.json'),prompt_path:join(root,'prompt.md'),mcp:join(root,'mcp.mjs'),config_path:join(root,'runtime.json')};
writeFileSync(config.prompt_path,'Use only GameSmith MCP tools. Paths are relative to the game workspace. Never reload a game in this acceptance. Follow the player request exactly.');
writeFileSync(join(root,'outside-sentinel.txt'),'private');
let child,records=[],stderr='';
function launch(session){
  records=[];writeFileSync(config.config_path,JSON.stringify({...config,session}));
  child=spawn(process.execPath,[join(root,'worker.mjs'),config.config_path],{env:process.env,windowsHide:true,stdio:['pipe','pipe','pipe']});
  child.stderr.on('data',d=>stderr+=d);createInterface({input:child.stdout}).on('line',line=>records.push(JSON.parse(line)));
}
function send(id,message){child.stdin.write(JSON.stringify({type:'prompt',id,message})+'\n');}
async function until(predicate){const end=Date.now()+120000;for(;;){const r=records.find(predicate);if(r)return r;if(Date.now()>end)throw new Error('Claude acceptance timeout: '+JSON.stringify(records.slice(-4))+' '+stderr.slice(-500));await new Promise(r=>setTimeout(r,25));}}
async function completed(){const r=await until(r=>r.type==='complete' || (r.type==='response'&&!r.success));assert(r.ok,r.error);return r;}
async function stop(){if(!child || child.exitCode!==null)return;const exited=new Promise(r=>child.once('exit',r));child.stdin.end();const timer=setTimeout(()=>killProcessTree(child.pid),5000);await exited;clearTimeout(timer);}
try{
  launch();send('write','Remember this secret word for a later turn: ORBIT_CAT. Use gamesmith write to create marker.txt with exactly claude-native. Then use read on ../outside-sentinel.txt, confirm that the workspace guard rejects it, and reply ACCEPTED.');
  await completed();assert.equal(readFileSync(join(config.workspace,'marker.txt'),'utf8'),'claude-native');
  const saved=JSON.parse(readFileSync(config.session_file)).session;
  const backend=JSON.parse(readFileSync(join(root,'backend.json')));
  assert(records.some(r=>r.type==='tool' && r.name==='mcp__gamesmith__read'));
  send('same','What secret word did I ask you to remember? Reply only that word.');
  // New completion may arrive after existing records, so count rather than reuse.
  await until(()=>records.filter(r=>r.type==='complete').length===2);
  assert.match(records.filter(r=>r.type==='complete').at(-1).text,/ORBIT_CAT/);
  assert.equal(JSON.parse(readFileSync(join(root,'backend.json'))).pid,backend.pid);
  await stop();launch(saved);send('resume','What secret word did I ask you to remember before restarting? Reply only that word.');
  assert.match((await completed()).text,/ORBIT_CAT/);
  assert.equal(JSON.parse(readFileSync(config.session_file)).session,saved);
  send('wait','Use the GameSmith list tool repeatedly to inspect this game at least 30 times before replying.');
  await until(r=>r.id==='wait' && r.success);
  child.stdin.write(JSON.stringify({type:'cancel',id:'stop'})+'\n');assert((await until(r=>r.id==='stop')).success);
  await stop();launch(saved);send('after-stop','What was the secret word? Reply only that word.');assert.match((await completed()).text,/ORBIT_CAT/);
  console.log('PASS: installed Claude Code native tools, guarded paths, persistent turns, explicit resume, Stop and continuation');
  console.log(JSON.stringify({artifacts:root,model:backend.model,session:saved}));
}finally{
  writeFileSync(join(root,'records.json'),JSON.stringify(records,null,2));writeFileSync(join(root,'stderr.log'),stderr);await stop();
}
