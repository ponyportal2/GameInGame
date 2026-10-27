#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { createWriteStream, existsSync, mkdirSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { selectTests, resolveTest, runHostTests } from './verification-plan.mjs';
import { atomicJson, assertionCounts, digest, failureExcerpt, fatalScriptError, fingerprint, git, reusedTests } from './verification-evidence.mjs';
import { killProcessTree } from '../agent/process-tree.mjs';

const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
export function parseArgs(args){
  const options={suite:'affected',output:'summary',jobs:4,timeout:600000,stall:60000,changed:[]};
  const values=new Set(['suite','output','jobs','timeout','stall','godot','artifacts','rerun-failed','reuse','changed','live','test']);
  for(let i=0;i<args.length;i++){
    const key=args[i].replace(/^--/,'');
    if(key==='help'){options.help=true;continue;}
    if(key==='build-package'){options.build=true;continue;}
    if(!args[i].startsWith('--')||!values.has(key)||args[i+1]===undefined)throw new Error('Unknown/missing option: '+args[i]);
    const value=args[++i];if(key==='changed')options.changed.push(...value.split(','));else options[key]=value;
  }
  for(const key of ['jobs','timeout','stall']){options[key]=Number(options[key]);if(!Number.isInteger(options[key])||options[key]<1)throw new Error('Invalid '+key);}
  if(!['summary','errors','full'].includes(options.output))throw new Error('Output must be summary, errors or full');
  if(options.reuse&&options['rerun-failed'])throw new Error('Reuse and failure rerun are separate operations');
  return options;
}

export async function runVerification(options,root=ROOT){
  const started=Date.now(),directory=options.artifacts?resolve(options.artifacts):mkdtempSync(join(tmpdir(),'gamesmith-verify-'));
  mkdirSync(directory,{recursive:true});
  const resultsPath=join(directory,'results.json');
  if(existsSync(resultsPath))throw new Error('Artifact directory already contains results.json; use a new directory');
  const godot=resolve(options.godot||process.env.GODOT_BIN||join(root,'GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe'));
  const changed=options.changed.length?options.changed:[...new Set([...git(root,['diff','--name-only','HEAD']).split('\n'),...git(root,['ls-files','--others','--exclude-standard']).split('\n')].filter(Boolean))];
  // Explicit selections and failed-only reruns do not consult unrelated changes.
  let tests=options.test||options['rerun-failed']||options.live?[]:selectTests(root,options.suite,changed);
  if(options['rerun-failed']){
    const prior=JSON.parse(readFileSync(resolve(options['rerun-failed']),'utf8'));
    // Invalidated evidence proves none of the original selection against the
    // current inputs, even when every individual process exited successfully.
    const failed=prior.inputs_changed?prior.selection:prior.tests.filter(t=>['failed','interrupted','blocked'].includes(t.status)&&!t.id.startsWith('setup:')&&!t.id.startsWith('build:')).map(t=>t.id);
    if(prior.tests.some(t=>t.id==='build:package'&&t.status==='failed'))options.build=true;
    tests=failed.map(id=>{if(id.startsWith('live:')){options.live=id.slice(5);return {id,phase:'host',file:'tests/'+options.live.replaceAll('-','_')+'_integration_runner.gd'};}return resolveTest(root,id);});
  }
  if(options.test)tests=options.test.split(',').map(id=>resolveTest(root,id));
  if(options.live){
    const id=options.live.replaceAll('-','_');
    if(!existsSync(join(root,'tests',id+'_integration_runner.gd')))throw new Error('Unknown live harness');
    if(options.live==='codex'&&!process.env.GAMESMITH_CODEX_BIN?.includes('codex-luna-launcher'))throw new Error('Codex live tests require GAMESMITH_CODEX_BIN pointing at tools/testing/codex-luna-launcher.mjs (explicit gpt-6-luna flag).');
    tests=[{id:'live:'+options.live,phase:'host',file:'tests/'+id+'_integration_runner.gd'}];
  }
  // The packaged tests read the tracked PCK, not the working tree. Editing the
  // runner's assertions, or any source the PCK compiles, must not run stale
  // bytes and count that as evidence for the change under test.
  const packaged=t=>t.id==='package:contents';
  if(tests.some(packaged)&&changed.some(p=>p==='tests/package_contents_runner.gd'||p==='tests/package_contents_runner.gd.uid'||p==='project.godot'||p.startsWith('src/')))options.build=true;
  const needsGodot=tests.some(t=>t.phase==='host'||t.phase==='acceptance'||t.id==='package:contents'||(t.phase==='node'&&readFileSync(join(root,t.file),'utf8').includes('assembled-runtime.mjs')))||options.build;
  const version=(bin,args)=>{const r=spawnSync(bin,args,{encoding:'utf8',windowsHide:true,timeout:10000});if(r.status!==0)return {unavailable:bin,error:r.error?.message||r.stderr?.trim()||'version probe failed'};return r.stdout.trim();};
  const runtimes={node:process.version,platform:process.platform,arch:process.arch};
  if(needsGodot)runtimes.godot={path:godot,version:version(godot,['--version']),sha256:existsSync(godot)?digest(readFileSync(godot)):null};
  for(const bin of ['python','go'])if(tests.some(t=>t.phase===(bin==='go'?'launcher':'package')))runtimes[bin]=version(bin,bin==='go'?['version']:['--version']);
  // Fixtures can exercise installed Blender. Record its resolved identity too.
  const {resolveBlender}=await import('../blender/jobs.mjs');
  const blender=tests.some(t=>/blender|game_assets|native_recovery/.test(t.id))?await resolveBlender().catch(()=>null):null;
  if(blender&&existsSync(blender))runtimes.blender={path:blender,version:version(blender,['--version']),sha256:digest(readFileSync(blender))};
  // Test artifacts and live global state must never be reused as fresh evidence.
  const selectedTests=[...tests];
  const evidence=fingerprint(root,tests,runtimes,process.env,[relative(root,directory).replaceAll('\\','/')]);
  const result={...evidence,results_path:resultsPath,started_at:new Date(started).toISOString(),suite:options.suite,jobs:options.jobs,status:'running',duration_ms:0,tests:[],selection:tests.map(t=>t.id),changed};
  const progress={phase:'starting',completed:0,total:tests.length,running:[],last_progress_at:new Date().toISOString()};
  const persist=()=>{result.duration_ms=Date.now()-started;atomicJson(resultsPath,result);atomicJson(join(directory,'progress.json'),progress);};
  let interrupted=false;
  const children=new Set();
  const stop=()=>{interrupted=true;for(const child of children)child.pid&&killProcessTree(child.pid);};
  process.once('SIGINT',stop);process.once('SIGTERM',stop);
  const phase=name=>{progress.phase=name;progress.last_progress_at=new Date().toISOString();persist();console.log('Phase: '+name);};
  const run=async(test,bin,args,env={},cwd=root)=>{
    if(interrupted)return;
    const time=Date.now(),log=join(directory,test.id.replaceAll(':','-')+'.log');
    const stream=createWriteStream(log);let text='',error='',timedOut=false,crashed=false;
    if(!result.selection.includes(test.id))progress.total++;
    progress.running.push(test.id);progress.last_progress_at=new Date().toISOString();persist();
    const childEnv={...process.env,GODOT_BIN:godot,...env};delete childEnv.NODE_TEST_CONTEXT;
    const child=spawn(bin,args,{cwd,env:childEnv,windowsHide:true,stdio:['ignore','pipe','pipe']});children.add(child);
    // A Godot script error inside the host project aborts the runner coroutine,
    // so quit() can never run and the deadline would wait out the full timeout.
    // Generated candidates under user:// are expected to fail parsing; only the
    // runner or the core code it drives is fatal.
    const consume=chunk=>{stream.write(chunk);text+=chunk.toString();if(options.output==='full')process.stdout.write(chunk);
      if(!crashed&&test.file?.endsWith('.gd')&&fatalScriptError(text.slice(-8192))){crashed=true;error='Godot script error aborted the test runner';child.pid&&killProcessTree(child.pid);}};
    child.stdout.on('data',consume);child.stderr.on('data',consume);
    child.once('error',e=>{error=e.message;consume(Buffer.from('\n'+error+'\n'));});
    const timer=setTimeout(()=>{timedOut=true;error='Test deadline exceeded';child.pid&&killProcessTree(child.pid);},options.timeout);
    const stall=setInterval(()=>console.log('Still running: '+test.id+'; progress: '+join(directory,'progress.json')),options.stall);
    const code=await new Promise(resolve=>child.once('close',resolve));clearTimeout(timer);clearInterval(stall);children.delete(child);
    await new Promise(resolve=>stream.end(resolve));
    const entry={id:test.id,status:interrupted?'interrupted':code===0&&!timedOut&&!crashed?'passed':'failed',exit_code:code,duration_ms:Date.now()-time,assertions:assertionCounts(text,test.phase),log};
    if(entry.status!=='passed'){
      const excerpt=failureExcerpt(text);const diagnostic=join(directory,test.id.replaceAll(':','-')+'.diagnostic.json');
      atomicJson(diagnostic,{...excerpt,error:error||null,exit_code:code});entry.diagnostics=[{file:diagnostic,log,start_line:excerpt.start_line,end_line:excerpt.end_line}];
      console.log('FAIL: '+test.id+'; '+log);
      if(options.output==='errors')console.log(excerpt.text);
    }
    result.tests.push(entry);progress.running=progress.running.filter(id=>id!==test.id);progress.completed++;progress.last_progress_at=new Date().toISOString();persist();return entry;
  };
  try{
    persist();
    let reused=[];
    if(options.reuse&&!options.live&&!options.build&&!tests.some(t=>t.phase==='acceptance')){const prior=JSON.parse(readFileSync(resolve(options.reuse),'utf8'));reused=reusedTests(prior,tests,evidence.fingerprint);result.tests.push(...reused);progress.completed=reused.length;persist();}
    tests=tests.filter(t=>!reused.some(r=>r.id===t.id));
    if(options.build){phase('build-package');const r=await run({id:'build:package',phase:'build'},godot,['--headless','--path',root,'--export-pack','Linux Pack',join(root,'GameSmith-Windows/GameSmith.pck')]);if(r.status!=='passed')throw new Error('Package build failed');Object.assign(result,fingerprint(root,selectedTests,runtimes,process.env,[relative(root,directory).replaceAll('\\','/')]));}
    let imported;
    if(needsGodot&&tests.length){phase('godot-import');imported=await run({id:'setup:godot',phase:'setup'},godot,['--headless','--path',root,'--editor','--quit'],{APPDATA:join(directory,'import-data'),HOME:join(directory,'import-data'),XDG_DATA_HOME:join(directory,'import-data/data')});}
    const node=tests.filter(t=>t.phase==='node');
    if(node.length&&(!imported||imported.status==='passed')){phase('node');let next=0;await Promise.all(Array.from({length:Math.min(options.jobs,node.length)},async()=>{while(next<node.length&&!interrupted){const test=node[next++];await run(test,process.execPath,['--test','--test-reporter=tap',test.file]);}}));}
    if(imported?.status==='failed')for(const t of node){result.tests.push({id:t.id,status:'blocked',reason:'Godot import failed'});progress.completed++;}
    const host=tests.filter(t=>t.phase==='host'||t.id==='package:contents');
    if(host.length){
      if(imported.status==='passed'){
        phase('godot-host');
        await runHostTests(host,options.jobs,async test=>{
          const data=join(directory,test.id.replaceAll(':','-')+'-data');mkdirSync(data,{recursive:true});
          const env={APPDATA:data,HOME:data,XDG_DATA_HOME:join(data,'data')};
          // Real CLI login remains native-owned; fixture suites stay isolated.
          if(options.live){const {liveEnvironment}=await import('./verification-live.mjs');Object.assign(env,liveEnvironment(options.live,process.env));}
          const args=test.id==='package:contents'?['--main-pack',join(root,'GameSmith-Windows/GameSmith.pck')]:['--path',root];
          await run(test,godot,['--headless',...args,'--log-file',join(data,'engine.log'),'--script','res://'+test.file],env,test.id==='package:contents'?data:root);
        },()=>interrupted);
      }else for(const test of host){result.tests.push({id:test.id,status:'blocked',reason:'Godot import failed'});progress.completed++;}
    }
    for(const test of tests.filter(t=>t.id==='package:structure'||t.phase==='launcher')){
      phase(test.phase);if(test.phase==='launcher')await run(test,'go',['test','./...'],{},join(root,test.file));else await run(test,'python',[test.file]);
    }
    const acceptance=tests.filter(t=>t.phase==='acceptance');
    if(acceptance.length){phase('acceptance');for(const test of acceptance){
      if(test.id==='acceptance:pi-emulator')await run(test,process.execPath,[test.file,godot]);
      else if(test.id==='acceptance:migration')await run(test,process.execPath,[test.file,godot]);
      else if(process.platform==='win32'||process.env.DISPLAY)await run(test,godot,['--path',root,'--script','res://'+test.file],{APPDATA:join(directory,'windowed'),HOME:join(directory,'windowed'),XDG_DATA_HOME:join(directory,'windowed/data')});
      else if(spawnSync('xvfb-run',['--help'],{windowsHide:true}).status===0)await run(test,'xvfb-run',['-a',godot,'--path',root,'--script','res://'+test.file],{HOME:join(directory,'windowed')});
      else {result.tests.push({id:test.id,status:'skipped',reason:'No display or xvfb-run available'});progress.completed++;}
    }}
    result.status=interrupted?'interrupted':result.tests.some(t=>!['passed','reused','skipped'].includes(t.status))?'failed':'passed';
  }catch(error){result.status='failed';result.error=error.message;console.log('FAIL: '+error.message);}
  finally{for(const test of tests)if(!result.tests.some(t=>t.id===test.id)){result.tests.push({id:test.id,status:interrupted?'interrupted':'blocked',reason:result.error||'Execution interrupted'});progress.completed++;}
    const finalEvidence=fingerprint(root,selectedTests,runtimes,process.env,[relative(root,directory).replaceAll('\\','/')]);
    if(finalEvidence.fingerprint!==result.fingerprint){result.inputs_changed=true;result.status='failed';result.error='Inputs changed during verification; results cannot be reused.';console.log('FAIL: '+result.error);}
    process.off('SIGINT',stop);process.off('SIGTERM',stop);progress.phase=result.status;persist();}
  const counts=Object.fromEntries(['passed','failed','blocked','interrupted','reused','skipped'].map(s=>[s,result.tests.filter(t=>t.status===s).length]));
  result.assertions={passed:0,failed:0,skipped:0};for(const entry of result.tests)for(const key of Object.keys(result.assertions))result.assertions[key]+=entry.assertions?.[key]||0;persist();
  console.log(`${result.status.toUpperCase()}: ${JSON.stringify(counts)}; ${(result.duration_ms/1000).toFixed(1)}s\nResults: ${resultsPath}`);
  return result;
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{const options=parseArgs(process.argv.slice(2));if(options.help)console.log('verify --suite affected|smoke|full|all|release|acceptance|node|host|package|launcher|<harness> --output summary|errors|full [--godot path] [--jobs 4] [--rerun-failed results.json] [--reuse results.json] [--changed paths] [--test id,id] [--build-package] [--live harness]');else process.exitCode=(await runVerification(options)).status==='passed'?0:1;}
  catch(error){console.error(error.message);process.exitCode=2;}
}
