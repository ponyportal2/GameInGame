import {spawn} from 'node:child_process';
import {readFile,writeFile,rename,mkdir,readdir,stat,access} from 'node:fs/promises';
import {join,dirname,delimiter,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {workspacePath} from './workspace-paths.mjs';
import {killProcessTree} from './process-tree.mjs';

export async function resolveBlender(env=process.env) {
  if(env.GAMESMITH_BLENDER_BIN) {
    try {await access(env.GAMESMITH_BLENDER_BIN);return env.GAMESMITH_BLENDER_BIN;}
    catch {throw new Error('Blender executable not found: GAMESMITH_BLENDER_BIN.');}
  }
  const candidates=(env.PATH || '').split(delimiter).filter(Boolean).map(p=>join(p,process.platform==='win32'?'blender.exe':'blender'));
  if(process.platform==='win32') {
    const root=join(env.ProgramFiles || 'C:/Program Files','Blender Foundation');
    for(const entry of (await readdir(root).catch(()=>[])).sort((a,b)=>b.localeCompare(a,undefined,{numeric:true})))
      candidates.push(join(root,entry,'blender.exe'));
  } else if(process.platform==='darwin') candidates.push('/Applications/Blender.app/Contents/MacOS/Blender');
  for(const candidate of candidates)try {if((await stat(candidate)).isFile())return candidate;}catch{}
  throw new Error('Blender was not found. Install Blender, add it to PATH, or set GAMESMITH_BLENDER_BIN to its executable.');
}
export async function prepareJob(config) {
  if(!config.script && !config.blend)throw new Error('Provide a workspace .py script or .blend file.');
  const result={...config,workspace:resolve(config.workspace)};
  for(const [key,extension] of [['script','.py'],['blend','.blend'],['render','.png']])if(config[key]) {
    if(typeof config[key]!=='string' || !config[key].toLowerCase().endsWith(extension))throw new Error(key+' must be a relative '+extension+' path.');
    result[key]=await workspacePath(result.workspace,config[key],{destructive:true});
    if(key==='render')await mkdir(dirname(result[key]),{recursive:true});
    else if(!(await stat(result[key])).isFile())throw new Error(key+' is not a file.');
  }
  return result;
}
export async function inspectImage(workspace,path) {
  const file=await workspacePath(workspace,path,{destructive:true});
  if((await stat(file)).size>8*1024*1024)throw new Error('Preview exceeds 8 MiB; render a smaller PNG.');
  const data=await readFile(file);
  if(data.length<33 || !data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || data.toString('ascii',12,16)!=='IHDR')throw new Error('Expected a PNG preview.');
  const width=data.readUInt32BE(16),height=data.readUInt32BE(20);
  if(!width || !height || width>4096 || height>4096 || width*height>4194304)throw new Error('Preview is too large; render at 1024 pixels or less for inspection.');
  return {ok:true,path,mime_type:'image/png',width,height,image_base64:data.toString('base64')};
}
export async function runJob(config) {
  let child,closed=false,stopped=false,tail='',dropped=0,timer;
  const statusFile=join(config.directory,'status.json');
  let status={ok:true,run_id:config.run_id,state:'starting'};
  // Serialize status writes: no overlapping .tmp writers, including final exit.
  let writes=Promise.resolve();
  const save=()=>{const payload=JSON.stringify({...status,log_tail:tail,log_dropped_bytes:dropped});writes=writes.then(async()=>{await writeFile(statusFile+'.tmp',payload);await rename(statusFile+'.tmp',statusFile);});return writes;};
  const capture=data=>{tail+=data.toString();if(tail.length>32768){dropped+=tail.length-32768;tail=tail.slice(-32768);}};
  const stop=()=>{if(closed || stopped)return;stopped=true;if(child?.pid)killProcessTree(child.pid);};
  process.stdin.resume();process.stdin.on('end',stop);
  const onSignal=()=>stop();process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
  try {
    await save();
    const executable=await resolveBlender();
    const prepared=await prepareJob(config);
    // Do not allow inherited startup files/preferences/add-ons to alter this job.
    const privateHome=join(config.directory,'blender-config');await mkdir(privateHome,{recursive:true});
    const args=['--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',join(dirname(fileURLToPath(import.meta.url)),'bootstrap.py'),'--',join(config.directory,'prepared.json')];
    await writeFile(join(config.directory,'prepared.json'),JSON.stringify(prepared));
    if(stopped)throw new Error('Blender job cancelled before launch.');
    child=spawn(executable,args,{cwd:prepared.workspace,windowsHide:true,env:{...process.env,BLENDER_USER_CONFIG:privateHome,BLENDER_USER_SCRIPTS:join(privateHome,'scripts'),GAMESMITH_WORKSPACE:prepared.workspace},stdio:['ignore','pipe','pipe']});
    child.stdout.on('data',capture);child.stderr.on('data',capture);
    status={...status,state:'running',pid:child.pid,executable};await save();
    timer=setInterval(()=>{
      try {process.kill(config.parent_pid,0);}catch{stop();}
      if(!stopped)void access(join(config.directory,'stop')).then(stop,()=>{});
      void save();
    },300);
    const exit=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
    closed=true;
    const report=await readFile(join(config.directory,'report.json'),'utf8').then(JSON.parse,()=>undefined);
    status={...status,state:stopped?'cancelled':exit.code===0?'completed':'failed',ok:!stopped && exit.code===0,exit_code:exit.code,signal:exit.signal,report};
    if(!status.ok)status.error=stopped?'Blender job cancelled.':'Blender failed. Read log_tail, fix the bpy script and run again.';
  }catch(error){if(child?.pid && !closed)stop();status={...status,ok:false,state:stopped?'cancelled':'failed',error:error.message};}
  finally {clearInterval(timer);closed=true;process.stdin.removeListener('end',stop);process.stdin.pause();process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);await save();}
  return status;
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  if(process.argv[2]==='--inspect') {
    try {console.log(JSON.stringify(await inspectImage(process.argv[3],process.argv[4])));}
    catch(error){console.log(JSON.stringify({ok:false,error:error.message}));process.exitCode=1;}
  } else {
    try {await runJob(JSON.parse(await readFile(process.argv[2],'utf8')));}
    catch(error){console.error(error.message);process.exitCode=1;}
  }
}
