import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import { killProcessTree } from '../tools/agent/process-tree.mjs';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function alive(pid) {
  if(process.platform==='win32') {try {process.kill(pid,0);return true;} catch {return false;}}
  const result=spawnSync('ps',['-p',String(pid),'-o','stat='],{encoding:'utf8'});
  return result.status===0 && result.stdout.trim() && !result.stdout.trim().startsWith('Z');
}
test('shutdown kills a detached descendant before pipe EOF can orphan it', async()=>{
  const root=await mkdtemp(join(tmpdir(),'gamesmith-tree-'));
  const path=join(root,'pids.json');
  const child=spawn(process.execPath,['tools/testing/fake-launcher-race.mjs',path],{windowsHide:true});
  const closed=once(child,'close');let pids;
  try {
    for(let n=0;n<100;n++){try {pids=JSON.parse(await readFile(path,'utf8'));break;}catch {await delay(10);}}
    assert.ok(pids);
    killProcessTree(child.pid);await closed;
    for(let n=0;n<100 && alive(pids.child);n++) await delay(10);
    assert.equal(!!alive(pids.child),false);
  } finally {if(child.exitCode===null) {killProcessTree(child.pid);await closed;}if(pids && alive(pids.child)) process.kill(pids.child,'SIGKILL');}
});
