// Recovery is only for a still-identical process carrying this job's private path.
// Never tree-kill a PID solely because it appeared in an old status file.
import {spawnSync} from 'node:child_process';
import {readFile,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {killProcessTree} from './process-tree.mjs';

export async function processIdentity(pid) {
  if(!Number.isInteger(pid) || pid<=1 || pid===process.pid)return null;
  if(process.platform==='win32') {
    const command=`$p=Get-CimInstance Win32_Process -Filter 'ProcessId=${pid}'; if($p){ @{birth=$p.CreationDate.ToUniversalTime().Ticks.ToString();exe=$p.ExecutablePath;command=$p.CommandLine} | ConvertTo-Json -Compress }`;
    const result=spawnSync(join(process.env.SystemRoot || 'C:/Windows','System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-NonInteractive','-Command',command],{windowsHide:true,encoding:'utf8',timeout:10000});
    if(result.error || result.status!==0)throw new Error('Could not inspect Blender process ownership.');
    return result.stdout.trim()?JSON.parse(result.stdout.trim()):null;
  }
  if(process.platform==='linux') {
    try {
      const stat=await readFile(`/proc/${pid}/stat`,'utf8');
      return {birth:stat.slice(stat.lastIndexOf(')')+2).split(' ')[19],exe:await realpath(`/proc/${pid}/exe`),command:(await readFile(`/proc/${pid}/cmdline`,'utf8')).replaceAll('\0',' ')};
    }catch(error){if(['ENOENT','ESRCH'].includes(error.code))return null;throw error;}
  }
  const result=spawnSync('/bin/ps',['-p',String(pid),'-o','lstart=','-o','command='],{encoding:'utf8'});
  if(result.status===1 && !result.stdout.trim())return null;
  if(result.error || result.status!==0)throw new Error('Could not inspect Blender process ownership.');
  return {birth:result.stdout.slice(0,24),command:result.stdout.slice(24).trim()};
}

export async function cleanupJob(config) {
  const status=JSON.parse(await readFile(join(config.directory,'status.json'),'utf8'));
  if(status.run_id!==config.run_id)throw new Error('Blender job ownership mismatch.');
  const current=await processIdentity(status.pid);
  if(!current)return {ok:true,killed:false};
  let previous=status.identity;
  const marker=join(config.directory,'prepared.json');
  if(!previous) {
    // The supervisor may die while recording the birth identity. An exact
    // random job path plus executable can still establish ownership now.
    const expected=await realpath(status.executable || '').catch(()=>resolve(status.executable || ''));
    const executable=current.exe || '';
    const sameExecutable=process.platform==='win32'?executable.toLowerCase()===expected.toLowerCase():executable===expected;
    if(!sameExecutable || !current.command.includes(marker))throw new Error('Missing verified Blender process ownership; refusing to kill a saved PID.');
    previous=current;
  }
  if(!previous.birth || !previous.command?.includes(marker))
    throw new Error('Missing verified Blender process ownership; refusing to kill a saved PID.');
  if(current.birth!==previous.birth || current.command!==previous.command || current.exe!==previous.exe)
    return {ok:true,killed:false}; // Exited, or PID was reused. Do not touch it.
  const confirmed=await processIdentity(status.pid);
  if(!confirmed || confirmed.birth!==current.birth || confirmed.command!==current.command || confirmed.exe!==current.exe)return {ok:true,killed:false};
  killProcessTree(status.pid);
  const after=await processIdentity(status.pid);
  if(after && after.birth===previous.birth && after.command===previous.command)
    throw new Error('Owned Blender process is still running after cleanup.');
  return {ok:true,killed:true};
}
