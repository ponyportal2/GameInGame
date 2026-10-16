import {spawn} from 'node:child_process';
import {readFile,writeFile,rename,mkdir,readdir,stat,access} from 'node:fs/promises';
import {join,dirname,delimiter,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {workspacePath} from './workspace-paths.mjs';
import {killProcessTree} from './process-tree.mjs';
import {createHash} from 'node:crypto';
import {StringDecoder} from 'node:string_decoder';
import {processIdentity,cleanupJob} from './ownership.mjs';

const sha256=data=>createHash('sha256').update(data).digest('hex');
// Warnings are retained independently of render progress and the rolling tail.
export function warningCapture() {
  const warnings=[],seen=new Set(),streams=new Map();let dropped=0;
  const line=text=>{
    text=text.replace(/\x1b\[[0-9;]*m/g,'').trim();
    if(!/\b(?:\w*warning|warn|error|unsupported|fallback)\b|\b(?:not\s+supported|falling\s+back)\b/i.test(text))return;
    text=text.slice(0,384);
    if(seen.has(text))return;
    if(warnings.length===16){dropped++;return;}
    seen.add(text);warnings.push(text);
  };
  return {
    push(data,stream='stdout') {
      if(!streams.has(stream))streams.set(stream,{decoder:new StringDecoder('utf8'),pending:''});
      const state=streams.get(stream),parts=(state.pending+state.decoder.write(data)).split(/\r\n|[\r\n]/);
      state.pending=parts.pop().slice(0,4096);
      for(const part of parts)line(part);
    },
    finish(){for(const state of streams.values()){line(state.pending+state.decoder.end());state.pending='';}},
    snapshot:()=>({warnings:[...warnings],warnings_dropped:dropped})
  };
}
export function blenderEnvironment(env,privateHome,workspace) {
  const allowed=new Set(['systemroot','windir','temp','tmp','tmpdir','home','userprofile','appdata','localappdata','lang','lc_all','display','wayland_display','xdg_runtime_dir']);
  return {...Object.fromEntries(Object.entries(env).filter(([key])=>allowed.has(key.toLowerCase()))),BLENDER_USER_CONFIG:privateHome,BLENDER_USER_SCRIPTS:join(privateHome,'scripts'),GAMESMITH_WORKSPACE:workspace};
}
export async function reviewScript(config) {
  const prepared=await prepareJob(config);
  if(!prepared.script)throw new Error('No Python script to review.');
  if((await stat(prepared.script)).size>256*1024)throw new Error('Script exceeds the 256 KiB review limit. Split the asset workflow into smaller scripts.');
  const bytes=await readFile(prepared.script);
  if(bytes.length>256*1024)throw new Error('Script exceeds the 256 KiB review limit.');
  const source=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  if(source.includes('\0'))throw new Error('Script contains non-displayable NUL bytes.');
  await writeFile(join(config.directory,'approved.py'),bytes);
  return {ok:true,script:config.script,source,sha256:sha256(bytes)};
}
export async function approvedJob(config) {
  const prepared=await prepareJob(config);
  if(!prepared.script)return prepared;
  if(!/^[a-f0-9]{64}$/.test(config.script_sha256 || ''))throw new Error('Player approval is required before running Blender Python.');
  if(sha256(await readFile(prepared.script))!==config.script_sha256)throw new Error('Script changed after review. Request fresh player approval.');
  const snapshot=join(config.directory,'approved.py');
  if(sha256(await readFile(snapshot))!==config.script_sha256)throw new Error('Approved script snapshot changed. Request fresh player approval.');
  return {...prepared,script:snapshot};
}

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
  const diagnostic=warningCapture();
  const statusFile=join(config.directory,'status.json');
  let status={ok:true,run_id:config.run_id,state:'starting'};
  // Serialize status writes: no overlapping .tmp writers, including final exit.
  let writes=Promise.resolve();
  const save=()=>{const payload=JSON.stringify({...status,...diagnostic.snapshot(),log_tail:tail,log_dropped_bytes:dropped});writes=writes.then(async()=>{await writeFile(statusFile+'.tmp',payload);await rename(statusFile+'.tmp',statusFile);});return writes;};
  const capture=(data,stream)=>{diagnostic.push(data,stream);tail+=data.toString();if(tail.length>32768){dropped+=tail.length-32768;tail=tail.slice(-32768);}};
  const stop=()=>{if(closed || stopped)return;stopped=true;if(child?.pid)killProcessTree(child.pid);};
  process.stdin.resume();process.stdin.on('end',stop);
  const onSignal=()=>stop();process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
  try {
    await save();
    const executable=await resolveBlender();
    const prepared=await approvedJob(config);
    // Do not allow inherited startup files/preferences/add-ons to alter this job.
    const privateHome=join(config.directory,'blender-config');await mkdir(privateHome,{recursive:true});
    const args=['--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',join(dirname(fileURLToPath(import.meta.url)),'bootstrap.py'),'--',join(config.directory,'prepared.json')];
    await writeFile(join(config.directory,'prepared.json'),JSON.stringify(prepared));
    if(stopped)throw new Error('Blender job cancelled before launch.');
    child=spawn(executable,args,{cwd:prepared.workspace,windowsHide:true,env:blenderEnvironment(process.env,privateHome,prepared.workspace),stdio:['ignore','pipe','pipe']});
    // Attach error/close handlers before querying ownership (the child may exit).
    const completion=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
    completion.catch(()=>{});
    child.stdout.on('data',data=>capture(data,'stdout'));child.stderr.on('data',data=>capture(data,'stderr'));
    status={...status,state:'running',pid:child.pid,executable};await save();
    const identity=await processIdentity(child.pid);
    status={...status,state:'running',pid:child.pid,executable,identity};await save();
    timer=setInterval(()=>{
      try {process.kill(config.parent_pid,0);}catch{stop();}
      if(!stopped)void access(join(config.directory,'stop')).then(stop,()=>{});
      void save();
    },300);
    const exit=await completion;
    closed=true;
    const report=await readFile(join(config.directory,'report.json'),'utf8').then(JSON.parse,()=>undefined);
    status={...status,state:stopped?'cancelled':exit.code===0?'completed':'failed',ok:!stopped && exit.code===0,exit_code:exit.code,signal:exit.signal,report};
    if(!status.ok)status.error=stopped?'Blender job cancelled.':'Blender failed. Read log_tail, fix the bpy script and run again.';
  }catch(error){if(child?.pid && !closed)stop();status={...status,ok:false,state:stopped?'cancelled':'failed',error:error.message};}
  finally {clearInterval(timer);closed=true;process.stdin.removeListener('end',stop);process.stdin.pause();process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);diagnostic.finish();await save();}
  return status;
}
if(process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  if(['--review','--cleanup'].includes(process.argv[2])) {
    try {
      const config=JSON.parse(await readFile(process.argv[3],'utf8'));
      console.log(JSON.stringify(await (process.argv[2]==='--review'?reviewScript(config):cleanupJob(config))));
    }catch(error){console.log(JSON.stringify({ok:false,error:error.message}));process.exitCode=1;}
  } else if(process.argv[2]==='--inspect') {
    try {console.log(JSON.stringify(await inspectImage(process.argv[3],process.argv[4])));}
    catch(error){console.log(JSON.stringify({ok:false,error:error.message}));process.exitCode=1;}
  } else {
    try {await runJob(JSON.parse(await readFile(process.argv[2],'utf8')));}
    catch(error){console.error(error.message);process.exitCode=1;}
  }
}
