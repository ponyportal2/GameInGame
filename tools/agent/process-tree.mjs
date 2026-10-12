import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function killProcessTree(root) {
  if (!Number.isInteger(root) || root <= 1 || root===process.pid) throw new Error('Invalid process-tree root');
  if (process.platform==='win32') {
    const result=spawnSync('taskkill.exe',['/PID',String(root),'/T','/F'],{windowsHide:true,stdio:'ignore'});
    if (result.error) throw result.error;
    return;
  }
  const stopped=new Set();
  const signal=(pid,kind)=>{try {process.kill(pid,kind);return true;} catch(error) {if(error.code!=='ESRCH') throw error;return false;}};
  try {
    if (!signal(root,'SIGSTOP')) return;
    stopped.add(root);
    // Freeze each discovered generation before rescanning. Detached process
    // groups remain descendants; no child can fork once this closure is frozen.
    for (;;) {
      const result=spawnSync('ps',['-eo','pid=,ppid='],{encoding:'utf8'});
      if(result.status!==0) throw new Error('Could not enumerate the agent process tree');
      const rows=result.stdout.trim().split(/\n/).map(line=>line.trim().split(/\s+/).map(Number));
      let changed=false;
      for (const [pid,parent] of rows) {
        if (stopped.has(parent) && !stopped.has(pid) && signal(pid,'SIGSTOP')) {stopped.add(pid);changed=true;}
      }
      if (!changed) break;
    }
    for (const pid of [...stopped].reverse()) signal(pid,'SIGKILL');
  } finally {
    for (const pid of stopped) {try {process.kill(pid,'SIGCONT');} catch {}}
  }
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try {killProcessTree(Number(process.argv[2]));}
  catch(error) {console.error(error.message);process.exitCode=1;}
}
