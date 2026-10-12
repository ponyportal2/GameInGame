import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
async function owner(workspace) {
  const child=spawn(process.execPath,['tools/agent/ownership.mjs',workspace],{windowsHide:true});
  const closed=once(child,'close');
  const ready=new Promise(resolve=>{createInterface({input:child.stdout}).once('line',line=>resolve(JSON.parse(line)));child.once('close',()=>resolve({ok:false,error:'No ownership helper response'}));});
  return {child,closed,result:await ready};
}
test('OS ownership excludes a second writer, separates games, and recovers after owner death', async()=>{
  const root=await mkdtemp(join(tmpdir(),'game-ownership-'));
  const first=await owner(root), second=await owner(root);
  let other, recovered;
  try {
    assert.equal(first.result.ok,true);
    assert.equal(second.result.ok,false);
    other=await owner(join(root,'different-game'));
    assert.equal(other.result.ok,true);
    first.child.kill();await first.closed;
    recovered=await owner(root);
    assert.equal(recovered.result.ok,true);
  } finally {
    for (const entry of [first,second,other,recovered].filter(Boolean)) {if(entry.child.exitCode===null) entry.child.stdin.end();await entry.closed;}
  }
});
