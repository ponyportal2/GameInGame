import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { OpenCodeAcpServer, resolveExecutable } from '../tools/opencode/server.mjs';
import { buildConfig } from '../tools/opencode/protocol.mjs';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';

const fixture=join(process.cwd(),'tools/testing/fake-opencode.mjs');
const mcp=join(process.cwd(),'tools/opencode/mcp.mjs');

test('Chocolatey launcher resolves to the native executable without a transient shim parent', async () => {
  const root=await mkdtemp(join(tmpdir(),'opencode-shim-'));
  const shim=join(root,'bin','opencode.exe');
  const native=join(root,'lib','opencode','tools','opencode.exe');
  await mkdir(join(root,'bin'),{recursive:true});await mkdir(join(root,'lib','opencode','tools'),{recursive:true});
  await writeFile(shim,'shim');await writeFile(native,'native');
  assert.equal(resolveExecutable(shim,'win32').bin,native);
});

test('OpenCode 2 npm launcher resolves to the packaged single-file binary', async () => {
  const root=await mkdtemp(join(tmpdir(),'opencode-npm-'));
  const shim=join(root,'opencode.cmd');
  const native=join(root,'node_modules','@opencode','cli','bin','opencode.exe');
  await mkdir(join(root,'node_modules','@opencode','cli','bin'),{recursive:true});
  await writeFile(shim,'shim');await writeFile(native,'native');
  assert.equal(resolveExecutable(shim,'win32').bin,native);
});

test('OpenCode startup rejection is explicitly initialization failure, not a failed model turn', {timeout:10000}, async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-opencode-init-'));
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,session_file:join(workspace,'session.json'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(workspace,'missing-opencode.exe')}});
  const closed=once(worker,'close');
  const response=new Promise((resolve,reject)=>{
    worker.once('error',reject);worker.once('exit',code=>reject(new Error('Worker exited before response: '+code)));
    createInterface({input:worker.stdout}).on('line',line=>{const r=JSON.parse(line);if(r.type==='response')resolve(r);});
  });
  try {
    worker.stdin.write(JSON.stringify({id:'init',type:'prompt',message:'hello'})+'\n');
    const result=await response;assert.equal(result.success,false);assert.equal(result.initialization_failed,true);
  } finally {worker.stdin.end();await closed;}
});

test('adapter streams before completion, rejects overlapping prompts during Stop and cleans up on EOF', {timeout:10000}, async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-worker-'));
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,name:'Stop fixture',session_file:join(workspace,'session.json'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:fixture}});
  const responses=new Map(), records=[];let serial=0;
  const closed=once(worker,'close');
  createInterface({input:worker.stdout}).on('line',line=>{
    const record=JSON.parse(line);records.push(record);
    if (record.type==='response') {responses.get(record.id)?.(record);responses.delete(record.id);}
  });
  function send(type,message) {
    const id=String(++serial);const response=new Promise(resolve=>responses.set(id,resolve));
    worker.stdin.write(JSON.stringify({id,type,message})+'\n');return response;
  }
  try {
    assert.equal((await send('prompt','wait')).success,true);
    while (!records.some(record=>record.type==='delta' && record.kind==='thinking')) await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(records.some(record=>record.type==='complete'),false);
    assert.equal(records.find(record=>record.type==='delta').text,'Fixture is thinking before completion');
    const backend=JSON.parse(await readFile(join(workspace,'backend.json'),'utf8'));
    assert.equal(backend.model,'fixture/model');
    const cancel=send('cancel');const overlap=send('prompt','follow up');
    assert.equal((await overlap).success,false);
    assert.equal((await cancel).success,true);
    assert.equal((await send('prompt','follow up')).success,true);
    while (!records.some(record=>record.type==='complete')) await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(records.filter(record=>record.type==='complete').length,1);
    assert.equal(records.find(record=>record.type==='complete').ok,true);
    assert.equal(records.find(record=>record.type==='complete').text,'Fixture finished');
    assert.equal(records.find(record=>record.type==='context').tokens,5120);
    assert.equal(JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid,backend.pid);
    assert.equal(JSON.parse(await readFile(config.session_file,'utf8')).session,'ses_fixture');
    process.kill(backend.pid,0);
    worker.stdin.end();await closed;
    assert.throws(()=>process.kill(backend.pid,0),{code:'ESRCH'});
  } finally {if (worker.exitCode===null) {worker.stdin.end();await closed;}}
});

test('persistent ACP transport keeps one backend across Stop and refuses an unknown session', async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-acp-'));
  const server=new OpenCodeAcpServer({workspace,executable:fixture,env:{...process.env,OPENCODE_CONFIG_CONTENT:JSON.stringify(buildConfig({mcp,prompt_path:join(workspace,'prompt.md')}))}});
  try {
    await server.start();const pid=server.pid;
    const session=await server.request('session/new',{cwd:workspace,mcpServers:[]});
    assert.equal(session.sessionId,'ses_fixture');
    assert.equal(session.configOptions.find(option=>option.id==='mode').currentValue,'build');
    const first=await server.request('session/prompt',{sessionId:session.sessionId,prompt:[{type:'text',text:'follow up'}]});
    assert.equal(first.stopReason,'end_turn');
    const pending=server.request('session/prompt',{sessionId:session.sessionId,prompt:[{type:'text',text:'wait'}]});
    server.notify('session/cancel',{sessionId:session.sessionId});
    assert.equal((await pending).stopReason,'cancelled');
    assert.equal(server.pid,pid);
    const next=await server.request('session/prompt',{sessionId:session.sessionId,prompt:[{type:'text',text:'follow up'}]});
    assert.equal(next.stopReason,'end_turn');
    assert.equal(server.pid,pid);
    await assert.rejects(server.request('session/load',{sessionId:'ses_missing',cwd:workspace,mcpServers:[]}),/session not found/);
  } finally {await server.close();}
});

test('stale OpenCode session retires the backend and preserves its reference',{timeout:10000},async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-opencode-stale-'));
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={session:'ses_missing',workspace,bridge_dir:workspace,name:'Stale fixture',session_file:join(workspace,'session.json'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  await writeFile(config.session_file,JSON.stringify({session:config.session}));
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:fixture}});
  const closed=once(worker,'close');
  const response=new Promise(resolve=>createInterface({input:worker.stdout}).on('line',line=>{const r=JSON.parse(line);if(r.type==='response')resolve(r);}));
  try {
    worker.stdin.write(JSON.stringify({id:'stale',type:'prompt',message:'hello'})+'\n');
    const result=await response;
    assert.equal(result.success,false);assert.equal(result.initialization_failed,true);assert.match(result.error,/Start a new OpenCode session/);
    assert.equal(JSON.parse(await readFile(config.session_file,'utf8')).session,'ses_missing');
    const backend=JSON.parse(await readFile(join(workspace,'backend.json'),'utf8'));
    assert.throws(()=>process.kill(backend.pid,0),{code:'ESRCH'});
  }finally{worker.stdin.end();await closed;}
});

async function contextFixture(workspace) {
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,name:'Context fixture',session_file:join(workspace,'session.json'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:fixture}});
  const records=[];createInterface({input:worker.stdout}).on('line',line=>records.push(JSON.parse(line)));
  const turn=async message=>{
    const before=records.filter(record=>record.type==='complete').length;
    worker.stdin.write(JSON.stringify({id:'turn'+before,type:'prompt',message})+'\n');
    for(;;){const done=records.filter(record=>record.type==='complete');if(done.length>before)return done[done.length-1];await new Promise(resolve=>setTimeout(resolve,10));}
  };
  const close=async()=>{worker.stdin.end();await once(worker,'close');};
  return {records,turn,close};
}

test('context occupancy comes from usage_update and survives an unchanged measurement',{timeout:20000},async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-opencode-context-'));
  const fixtureWorker=await contextFixture(workspace);
  try {
    assert.equal((await fixtureWorker.turn('one')).ok,true);
    // The second turn reports the same 5120 while its prompt usage is 120.
    assert.equal((await fixtureWorker.turn('two')).ok,true);
    assert.deepEqual(fixtureWorker.records.filter(record=>record.type==='context').map(record=>record.tokens),[5120,5120]);
    assert.equal(JSON.parse(await readFile(join(workspace,'session.json'),'utf8')).context_tokens,5120);
  } finally {await fixtureWorker.close();}
});

test('a turn without a usage_update leaves context unknown instead of using prompt totals',{timeout:20000},async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-opencode-context-'));
  const fixtureWorker=await contextFixture(workspace);
  try {
    assert.equal((await fixtureWorker.turn('context-missing')).ok,true);
    assert.equal(fixtureWorker.records.some(record=>record.type==='context'),false);
    assert.equal(JSON.parse(await readFile(join(workspace,'session.json'),'utf8')).context_tokens,null);
  } finally {await fixtureWorker.close();}
});
