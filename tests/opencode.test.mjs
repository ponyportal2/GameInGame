import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readdir, readFile, rename } from 'node:fs/promises';
import { buildArguments, buildConfig, normalizeFrame } from '../tools/opencode/protocol.mjs';
import plugin from '../tools/opencode/gamesmith.mjs';

test('OpenCode resumes only the explicit game session and receives no model/compaction overrides', () => {
  const args = buildArguments({session:'ses_game',name:'Fixture'}, 'literal $prompt & "quoted"');
  assert.deepEqual(args, ['run','--format','json','--thinking','--auto','--title','Fixture','--session','ses_game','--','literal $prompt & "quoted"']);
  const config = buildConfig({plugin:'C:/fixture/gamesmith.mjs',mcp:'C:/fixture/mcp.mjs',prompt_path:'C:/fixture/prompt.md'});
  for (const key of ['model','provider','compaction','small_model']) assert.equal(config[key], undefined);
  assert.equal(config.permission.bash,'ask');
  assert.equal(config.permission.read,'allow');
  assert.equal(config.permission['gamesmith_*'],'allow');
});

test('native JSON events preserve text, thinking, tool errors and current context including cache', () => {
  assert.deepEqual(normalizeFrame({type:'text',sessionID:'ses_a',part:{text:'Hello'}}), [{type:'session',session:'ses_a'},{type:'delta',kind:'assistant',text:'Hello'},{type:'assistant_text',text:'Hello'}]);
  assert.equal(normalizeFrame({type:'reasoning',part:{text:'Think'}})[0].kind,'thinking');
  const tool = normalizeFrame({type:'tool_use',part:{tool:'gamesmith_reload_game',state:{status:'error',error:'bad script'}}});
  assert.equal(tool[0].name,'gamesmith_reload_game');
  assert.equal(tool.at(-1).type,'status','finished native tools release the running-tool status');
  const end = normalizeFrame({type:'step_finish',part:{tokens:{input:100,output:20,reasoning:5,cache:{read:200,write:10}},reason:'tool-calls'}});
  assert.equal(end.find(e=>e.type==='context').tokens,335);
  assert.equal(end.some(e=>e.type==='complete'),false,'a tool round must not finish the player request');
  assert.equal(normalizeFrame({type:'error',error:{name:'APIError',data:{message:'provider failed'}}})[0].error,'provider failed');
});

test('plugin permits workspace tools and host tools but rejects shell, outside paths and .git writes', async () => {
  const dir = await mkdtemp(join(tmpdir(),'gamesmith-opencode-policy-'));
  const workspace = join(dir,'game'); await mkdir(workspace); await writeFile(join(workspace,'main.gd'),'extends Node');
  const hooks = await plugin({directory:workspace});
  const before = hooks['tool.execute.before'];
  await before({tool:'read'},{args:{filePath:join(workspace,'main.gd')}});
  await before({tool:'gamesmith_reload_game'},{args:{}});
  await before({tool:'gamesmith_test_game_action'},{args:{action:'inspect',path:'/root/Main'}});
  await assert.rejects(before({tool:'read'},{args:{filePath:join(dir,'outside')}}),/escapes/);
  await assert.rejects(before({tool:'write'},{args:{filePath:join(workspace,'.git','config')}}),/reserves/);
  await assert.rejects(before({tool:'bash'},{args:{command:'echo hi'}}),/unavailable/);
  await before({tool:'apply_patch'},{args:{patchText:'*** Begin Patch\n*** Add File: inside.gd\n+extends Node\n*** End Patch'}});
  await assert.rejects(before({tool:'apply_patch'},{args:{patchText:'*** Begin Patch\n*** Add File: ../outside.gd\n+bad\n*** End Patch'}}),/escapes/);
  await assert.rejects(before({tool:'apply_patch'},{args:{patchText:'*** Begin Patch\n*** Update File: .git/config\n+bad\n*** End Patch'}}),/reserves/);
  await assert.rejects(before({tool:'apply_patch'},{args:{patchText:'*** Begin Patch\n*** Update File: main.gd\n*** Move to: ../moved.gd\n*** End Patch'}}),/escapes/);
});

test('MCP approval waits send progress and preserve structured host failures as native tool errors', async () => {
  const directory=await mkdtemp(join(tmpdir(),'gamesmith-opencode-mcp-'));
  const child=spawn(process.execPath,['tools/opencode/mcp.mjs'],{env:{...process.env,GAMESMITH_HOST_BRIDGE_DIR:directory},stdio:['pipe','pipe','pipe']});
  const records=[];
  const lines=createInterface({input:child.stdout});lines.on('line',line=>records.push(JSON.parse(line)));
  const wait=async predicate=>{while (!predicate()) await new Promise(resolve=>setTimeout(resolve,10));};
  try {
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2024-11-05'}})+'\n');
    await wait(()=>records.some(r=>r.id===1));
    assert.equal(records.find(r=>r.id===1).result.protocolVersion,'2024-11-05');
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:2,method:'tools/list'})+'\n');
    await wait(()=>records.some(r=>r.id===2));
    // Assert the exact surface so adding or dropping a host tool is a deliberate edit.
    const expectedTools=['add_runtime_child','remove_runtime_child','rg_search','inspect_runtime','set_properties','generate_image','blender','reload_game','read_runtime_log','start_test_game','read_test_log','stop_test_game','test_game_action','git_status','git_diff','git_log','git_commit','delete_path','move_path'];
    assert.deepEqual(records.find(r=>r.id===2).result.tools.map(tool=>tool.name).sort(),[...expectedTools].sort());
    for(const name of ['inspect_runtime','set_properties','rg_search']) assert(records.find(r=>r.id===2).result.tools.some(tool=>tool.name===name));
    assert(records.find(r=>r.id===2).result.tools.some(tool=>tool.name==='generate_image'));
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'reload_game',arguments:{},_meta:{progressToken:'approval'}}})+'\n');
    await wait(()=>records.some(r=>r.method==='notifications/progress'));
    assert.equal(records.find(r=>r.method==='notifications/progress').params.progressToken,'approval');
    assert.equal(records.some(r=>r.id===3),false,'approval stays pending');
    const request=(await readdir(directory)).find(name=>/^request-.*\.json$/.test(name));
    const data=JSON.parse(await readFile(join(directory,request),'utf8'));
    assert.equal(data.command,'reload_game');
    const response=join(directory,request.replace('request-','response-'));
    await writeFile(response+'.tmp',JSON.stringify({ok:false,error:'Startup failed',diagnostics:{errors:['bad property']}}));
    await rename(response+'.tmp',response);
    await wait(()=>records.some(r=>r.id===3));
    const result=records.find(r=>r.id===3).result;
    assert.equal(result.isError,true);
    assert.equal(JSON.parse(result.content[0].text).diagnostics.errors[0],'bad property');
    const exited=once(child,'close');child.stdin.end();await exited;
  } finally {child.kill();lines.close();}
});
