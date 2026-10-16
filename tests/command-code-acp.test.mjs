import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';

async function fixture(t,mode='') {
  const dir=mkdtempSync(join(tmpdir(),'gs-command-acp-'));mkdirSync(join(dir,'bridge'));
  const runtime=assembleHarnessRuntime('command-code',join(dir,'adapter'));
  const config={workspace:dir,bridge_dir:join(dir,'bridge'),mod:join(runtime,'gamesmith.ts'),prompt_path:join(dir,'prompt.md'),session_file:join(dir,'session.json'),startup_timeout_ms:['missing-ready','wrong-nonce','missing-session-ready'].includes(mode)?1000:10000,session_id:mode==='load-failed'?'stale':''};
  writeFileSync(config.prompt_path,'GameSmith instructions');writeFileSync(join(dir,'config.json'),JSON.stringify(config));
  const child=spawn(process.execPath,[join(runtime,'worker.mjs'),join(dir,'config.json')],{env:{...process.env,GAMESMITH_COMMAND_CODE_BIN:resolve('tools/testing/fake-command-code.mjs'),GAMESMITH_FAKE_ACP:mode,GAMESMITH_FAKE_COMPACTION:mode.startsWith('compact-')?mode.slice(8):'summarized'},stdio:['pipe','pipe','pipe']});
  t.after(()=>child.stdin.end());let errors='';child.stderr.on('data',b=>errors+=b);const records=[],pending=new Map();
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);if(r.type==='response'){pending.get(r.id)?.(r);pending.delete(r.id);}});
  const command=(type,message)=>new Promise(resolve=>{const id=String(records.length)+'-'+Math.random();pending.set(id,resolve);child.stdin.write(JSON.stringify({id,type,message})+'\n');});
  const complete=async()=>{for(let n=0;n<400;n++){const r=records.findLast(r=>r.type==='complete');if(r)return r;await new Promise(r=>setTimeout(r,5));}throw new Error('Missing completion '+errors);};
  return {dir,records,command,complete,clear:()=>records.splice(0)};
}
test('persistent ACP reuses process/session for prompts and compact, excludes replay from streaming',async t=>{
  const f=await fixture(t);assert.equal((await f.command('prompt','hello')).success,true);assert.equal((await f.complete()).ok,true);
  const first=JSON.parse(readFileSync(join(f.dir,'backend.json')));f.clear();
  assert.equal((await f.command('compact')).data.ok,true);f.clear();
  await f.command('prompt','follow up');await f.complete();
  assert.equal(JSON.parse(readFileSync(join(f.dir,'backend.json'))).pid,first.pid);
  assert.equal(JSON.parse(readFileSync(join(f.dir,'session.json'))).session,'fixture-session');
});
for(const mode of ['missing-ready','wrong-nonce','missing-session-ready','load-failed'])test('fails closed before inference: '+mode,async t=>{
  const f=await fixture(t,mode);if(mode==='load-failed') {writeFileSync(join(f.dir,'session.json'),JSON.stringify({session:'stale'}));}
  const r=await f.command('prompt','hello');assert.equal(r.success,false);assert.equal(r.initialization_failed,true);
  assert.equal(f.records.some(r=>r.type==='delta'),false);
});
test('unknown permission/terminal requests are denied rather than inferred from titles',async t=>{
  const f=await fixture(t,'permissions');await f.command('prompt','hello');assert.equal((await f.complete()).ok,true);
  const answers=JSON.parse(readFileSync(join(f.dir,'permissions.json')));
  assert.equal(answers.permission.result.outcome.optionId,'deny');
  assert.equal(answers.terminal.error.code,-32601);
  assert.equal(answers.filesystem.error.code,-32601);
});

test('provider rejection after admission retires runtime without claiming initialization failed',async t=>{
  const f=await fixture(t);assert.equal((await f.command('prompt','provider-error')).success,true);
  const result=await f.complete();assert.equal(result.ok,false);assert.match(result.error,/Fixture provider error/);
  assert.equal(result.initialization_failed,false);assert.equal(result.runtime_failed,true);
});

test('policy failure after admission remains non-retryable',async t=>{
  const f=await fixture(t);assert.equal((await f.command('prompt','policy-error')).success,true);
  const result=await f.complete();assert.equal(result.ok,false);assert.match(result.error,/Fixture policy validation failed/);
  assert.equal(result.initialization_failed,true);assert.equal(result.runtime_failed,true);
});
for(const outcome of ['summarized','too-small','failed','unexpected'])test('persistent native compaction outcome: '+outcome,async t=>{
  const f=await fixture(t,'compact-'+outcome);await f.command('prompt','hello');await f.complete();
  const before=JSON.parse(readFileSync(join(f.dir,'backend.json'))).pid;f.clear();
  const r=await f.command('compact');assert.equal(r.success,['summarized','too-small'].includes(outcome));
  if(outcome==='too-small')assert.equal(r.data.no_op,true);
  f.clear();await f.command('prompt','after compact');assert.equal((await f.complete()).ok,true);
  if(outcome!=='unexpected')assert.equal(JSON.parse(readFileSync(join(f.dir,'backend.json'))).pid,before);
});
