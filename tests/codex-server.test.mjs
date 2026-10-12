import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { mkdtemp, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { CodexServer, resolveExecutable } from '../tools/codex/server.mjs';

test('Codex launcher resolves native executable and JS fixture without shell interpolation', () => {
  const bin=resolve('tools/testing/fake-codex.mjs');
  assert.deepEqual(resolveExecutable(bin),{bin:process.execPath,prefix:[bin]});
  if(process.platform==='win32') assert.deepEqual(resolveExecutable(process.execPath),{bin:process.execPath,prefix:[]});
});

test('persistent Codex adapter streams, interrupts, resumes explicitly and cleans backend on EOF', {timeout:15000},async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-codex-worker-'));
  const config={workspace,bridge_dir:workspace,session_file:join(workspace,'session.json'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  function launch() {
    const child=spawn(process.execPath,['tools/codex/worker.mjs',configPath],{windowsHide:true,env:{...process.env,GAMESMITH_CODEX_BIN:resolve('tools/testing/fake-codex.mjs')}});
    const records=[],pending=new Map();let serial=0;const closed=once(child,'close');child.stderr.resume();
    createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);pending.get(r.id)?.(r);pending.delete(r.id);});
    return {child,records,closed,send(type,message){const id=String(++serial);const promise=new Promise(resolveResult=>pending.set(id,resolveResult));child.stdin.write(JSON.stringify({id,type,message})+'\n');return promise;},async until(predicate){while(!predicate(records))await new Promise(r=>setTimeout(r,10));}};
  }
  let worker=launch(),backend;
  try {
    assert.equal((await worker.send('prompt','wait')).success,true);
    await worker.until(r=>r.some(x=>x.type==='delta' && x.kind==='thinking'));
    backend=JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid;
    const cancel=worker.send('cancel');const overlap=worker.send('prompt','overlap');
    assert.equal((await overlap).success,false);assert.equal((await cancel).success,true);
    assert.equal((await worker.send('prompt','follow up')).success,true);
    await worker.until(r=>r.some(x=>x.type==='complete'));
    assert.equal(worker.records.find(r=>r.type==='complete').text,'Fixture finished');
    assert.equal(worker.records.filter(r=>r.type==='delta' && r.kind==='assistant').map(r=>r.text).join(''),'Fixture finished');
    assert.equal(JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid,backend);
    assert.equal(JSON.parse(await readFile(config.session_file,'utf8')).context_tokens,5120);
    const count=worker.records.filter(r=>r.type==='complete').length;
    assert.equal((await worker.send('prompt','policy')).success,true);
    await worker.until(r=>r.filter(x=>x.type==='complete').length>count);
    assert.equal(worker.records.filter(r=>r.type==='complete').at(-1).ok,true);
    const requests=(await readFile(join(workspace,'.codex-fixture-requests.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(requests.filter(r=>r.method==='thread/start').length,1);
    assert.equal(requests.find(r=>r.method==='thread/start').params.config.mcp_servers.unrelated.enabled,false);
    for(const r of requests)for(const key of ['model','effort','modelProvider'])assert.equal(Object.hasOwn(r.params || {},key),false);
    worker.child.stdin.end();await worker.closed;assert.throws(()=>process.kill(backend,0),{code:'ESRCH'});
    config.session=JSON.parse(await readFile(config.session_file,'utf8')).session;await writeFile(configPath,JSON.stringify(config));
    worker=launch();assert.equal((await worker.send('prompt','provider-error')).success,true);
    await worker.until(r=>r.some(x=>x.type==='complete'));assert.equal(worker.records.find(r=>r.type==='complete').error,'Fixture provider error');
    const resumed=(await readFile(join(workspace,'.codex-fixture-requests.jsonl'),'utf8')).trim().split('\n').map(JSON.parse).find(r=>r.method==='thread/resume');
    assert.equal(resumed.params.threadId,config.session);
  }finally {if(worker.child.exitCode===null){worker.child.stdin.end();await worker.closed;}}
});

test('missing Codex executable rejects the app-server handshake',async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-codex-missing-'));
  const server=new CodexServer({workspace,executable:join(workspace,'missing-codex')});
  await assert.rejects(server.start());server.close();
});

test('native Codex backend death fails the active turn and retires the adapter', {timeout:5000},async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-codex-exit-'));
  const config={workspace,bridge_dir:workspace,session_file:join(workspace,'session.json'),prompt_path:join(workspace,'prompt.md')};
  const path=join(workspace,'runtime.json');await writeFile(path,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const child=spawn(process.execPath,['tools/codex/worker.mjs',path],{windowsHide:true,env:{...process.env,GAMESMITH_CODEX_BIN:resolve('tools/testing/fake-codex.mjs')}});
  const closed=once(child,'close'),records=[];child.stderr.resume();
  const started=new Promise(resolveStart=>createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);if(r.type==='delta')resolveStart();}));
  child.stdin.write(JSON.stringify({id:'death',type:'prompt',message:'wait'})+'\n');
  let timer;
  try {
    await started;
    process.kill(JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid);
    await Promise.race([closed,new Promise((_,reject)=>timer=setTimeout(()=>reject(new Error('Dead backend left its adapter alive')),1000))]);
    assert.equal(records.find(r=>r.type==='complete').ok,false);
  } finally {clearTimeout(timer);if(child.exitCode===null){child.stdin.end();await closed;}}
});
