import test from 'node:test';
import assert from 'node:assert/strict';
import { OpenCodeServer, resolveExecutable } from '../tools/opencode/server.mjs';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readFile } from 'node:fs/promises';

test('Chocolatey launcher resolves to the native executable without a transient shim parent', async () => {
  const root=await mkdtemp(join(tmpdir(),'opencode-shim-'));
  const shim=join(root,'bin','opencode.exe');
  const native=join(root,'lib','opencode','tools','opencode.exe');
  await mkdir(join(root,'bin'),{recursive:true});await mkdir(join(root,'lib','opencode','tools'),{recursive:true});
  await writeFile(shim,'shim');await writeFile(native,'native');
  assert.equal(resolveExecutable(shim,'win32').bin,native);
});

test('adapter streams before completion, rejects overlapping prompts during Stop and cleans up on EOF', {timeout:10000}, async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-worker-'));
  const config={workspace,bridge_dir:workspace,name:'Stop fixture',session_file:join(workspace,'session.json'),plugin:join(process.cwd(),'tools/opencode/gamesmith.mjs'),mcp:join(process.cwd(),'tools/opencode/mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,['tools/opencode/worker.mjs',configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(process.cwd(),'tools/testing/fake-opencode.mjs')}});
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
    const cancel=send('cancel');const overlap=send('prompt','follow up');
    assert.equal((await overlap).success,false);
    assert.equal((await cancel).success,true);
    assert.equal((await send('prompt','follow up')).success,true);
    while (!records.some(record=>record.type==='complete')) await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(records.filter(record=>record.type==='complete').length,1);
    assert.equal(records.find(record=>record.type==='complete').ok,true);
    assert.equal(JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid,backend.pid);
    process.kill(backend.pid,0);
    worker.stdin.end();await closed;
    assert.throws(()=>process.kill(backend.pid,0),{code:'ESRCH'});
  } finally {if (worker.exitCode===null) {worker.stdin.end();await closed;}}
});

test('persistent transport retains one server and native Stop aborts before another prompt starts', async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-server-'));
  const server=new OpenCodeServer({workspace,executable:join(process.cwd(),'tools/testing/fake-opencode.mjs'),env:{...process.env,OPENCODE_CONFIG_CONTENT:JSON.stringify({plugin:[],mcp:{}})}});
  try {
    await server.start();const pid=server.pid;
    const session=await server.request('/session','POST',{title:'Fixture'});
    const first=await server.request(`/session/${session.id}/message`,'POST',{parts:[{type:'text',text:'follow up'}]});
    assert.equal(first.info.finish,'stop');
    const pending=server.request(`/session/${session.id}/message`,'POST',{parts:[{type:'text',text:'wait'}]});
    await server.request(`/session/${session.id}/abort`,'POST');
    assert.equal((await pending).info.error.name,'MessageAbortedError');
    assert.equal(server.pid,pid);
    const next=await server.request(`/session/${session.id}/message`,'POST',{parts:[{type:'text',text:'follow up'}]});
    assert.equal(next.info.finish,'stop');
    assert.equal(server.pid,pid);
  } finally {await server.close();}
});

for (const message of ['partial-stream','lost-stream']) test(`HTTP final answer repairs ${message}`, {timeout:10000}, async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-final-'));
  const config={workspace,bridge_dir:workspace,name:'Final fixture',session_file:join(workspace,'session.json'),plugin:join(process.cwd(),'tools/opencode/gamesmith.mjs'),mcp:join(process.cwd(),'tools/opencode/mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,['tools/opencode/worker.mjs',configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(process.cwd(),'tools/testing/fake-opencode.mjs')}});
  const records=[]; const closed=once(worker,'close');
  const completion=new Promise(resolve=>createInterface({input:worker.stdout}).on('line',line=>{const record=JSON.parse(line);records.push(record);if(record.type==='complete') resolve(record);}));
  try {
    worker.stdin.write(JSON.stringify({id:'final',type:'prompt',message})+'\n');
    const result=await completion;
    assert.equal(result.ok,true);
    assert.equal(result.text,'I changed the player movement and fixed collisions.');
    assert.equal(records.filter(r=>r.type==='delta' && r.kind==='assistant').map(r=>r.text).join(''),result.text);
  } finally {worker.stdin.end();await closed;}
});
