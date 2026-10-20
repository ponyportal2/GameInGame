import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
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

test('OpenCode startup rejection is explicitly initialization failure, not a failed model turn', {timeout:10000}, async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-opencode-init-'));
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,session_file:join(workspace,'session.json'),plugin:join(runtime,'gamesmith.mjs'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
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
  const config={workspace,bridge_dir:workspace,name:'Stop fixture',session_file:join(workspace,'session.json'),plugin:join(runtime,'gamesmith.mjs'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(process.cwd(),'tools/testing/fake-opencode.mjs')}});
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
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,name:'Final fixture',session_file:join(workspace,'session.json'),plugin:join(runtime,'gamesmith.mjs'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(process.cwd(),'tools/testing/fake-opencode.mjs')}});
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

// Native owns history selection/compaction. This fixture tests our production
// worker across that event boundary, not OpenCode's summarizer or provider.
test('native compaction event preserves the current request, constraints and unfinished action through the adapter', {timeout:15000}, async()=>{
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-compact-boundary-'));
  const runtime=assembleHarnessRuntime('opencode',join(workspace,'adapter'));
  const config={workspace,bridge_dir:workspace,name:'Boundary fixture',session_file:join(workspace,'session.json'),plugin:join(runtime,'gamesmith.mjs'),mcp:join(runtime,'mcp.mjs'),prompt_path:join(workspace,'prompt.md')};
  const configPath=join(workspace,'runtime.json');await writeFile(configPath,JSON.stringify(config));await writeFile(config.prompt_path,'Fixture');
  const worker=spawn(process.execPath,[join(runtime,'worker.mjs'),configPath],{windowsHide:true,env:{...process.env,GAMESMITH_OPENCODE_BIN:join(process.cwd(),'tools/testing/fake-opencode.mjs')}});
  const records=[];const closed=once(worker,'close');
  createInterface({input:worker.stdout}).on('line',line=>records.push(JSON.parse(line)));
  const wait=async predicate=>{const deadline=Date.now()+10000;while(!predicate()){assert(Date.now()<deadline,'boundary deadline');await new Promise(r=>setTimeout(r,10));}};
  const taskB='Task B: add grenade on middle mouse; do not reload; pending action grenade-17';
  try {
    worker.stdin.write(JSON.stringify({id:'A',type:'prompt',message:'boundary-task-a'})+'\n');
    await wait(()=>records.filter(r=>r.type==='complete').length===1);
    const backend=JSON.parse(await readFile(join(workspace,'backend.json'),'utf8'));
    worker.stdin.write(JSON.stringify({id:'B',type:'prompt',message:taskB})+'\n');
    await wait(()=>records.filter(r=>r.type==='complete').length===2);
    const evidence=JSON.parse(await readFile(join(workspace,'.opencode-fixture-boundary.json'),'utf8'));
    assert.deepEqual(evidence.received,['boundary-task-a',taskB]);
    assert.equal(evidence.context[1].text,taskB);
    assert.equal(evidence.context[2].action_id,'grenade-17');
    const completions=records.filter(r=>r.type==='complete');
    assert(completions.every(r=>r.ok));
    assert.match(completions[1].text,/Task B grenade completed without reload/);
    assert.equal(JSON.parse(await readFile(join(workspace,'backend.json'),'utf8')).pid,backend.pid);
    assert.equal(JSON.parse(await readFile(config.session_file,'utf8')).session,'ses_fixture');
  } finally {worker.stdin.end();await closed;}
});
