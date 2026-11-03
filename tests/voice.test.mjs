import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

test('local voice worker validates audio, caches models, bounds output and cleans temporary recordings',()=>{
  const run=spawnSync('python',['tests/voice_worker_test.py'],{encoding:'utf8',windowsHide:true,timeout:30000});
  assert.equal(run.status,0,run.stdout+'\n'+run.stderr);
});
