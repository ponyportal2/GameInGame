import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';
import { readdir, readFile, rename } from 'node:fs/promises';
import { buildArguments, buildConfig, mergeConfig, normalizeFrame } from '../tools/opencode/protocol.mjs';
import workspacePlugin from '../tools/opencode/workspace-plugin.js';
import { symlink } from 'node:fs/promises';

test('native workspace hook resolves links and protects nested metadata, including new files', async () => {
  const root=await mkdtemp(join(tmpdir(),'opencode-guard-'));
  const workspace=join(root,'game'),outside=join(root,'outside');
  await mkdir(join(workspace,'nested','.git'),{recursive:true});await mkdir(outside);
  await writeFile(join(workspace,'file.txt'),'inside');await writeFile(join(outside,'secret'),'outside');
  await symlink(outside,join(workspace,'escape'),process.platform==='win32'?'junction':'dir');
  await symlink(join(workspace,'nested','.git'),join(workspace,'metadata-alias'),process.platform==='win32'?'junction':'dir');
  let before;
  await workspacePlugin.setup({location:{directory:workspace},tool:{hook:async(name,callback)=>{assert.equal(name,'execute.before');before=callback;}}});
  for (const [tool,path] of [['read','file.txt'],['write','new/file.txt'],['glob','.'],['grep','.']]) await before({tool,input:{path}});
  for (const [tool,path] of [['read',join(outside,'secret')],['read','escape/secret'],['write','escape/new/file'],['edit','nested/.git/config'],['write','metadata-alias/new/file'],['grep','escape']])
    await assert.rejects(before({tool,input:{path}}),/Permission denied/);
});

test('OpenCode resumes only the explicit game session and receives no model/compaction overrides', () => {
  const args = buildArguments({session:'ses_game',name:'Fixture'}, 'literal $prompt & "quoted"');
  assert.deepEqual(args, ['run','--format','json','--thinking','--auto','--title','Fixture','--session','ses_game','--','literal $prompt & "quoted"']);
  const config = buildConfig({mcp:'C:/fixture/mcp.mjs',prompt_path:'C:/fixture/prompt.md'});
  for (const key of ['model','provider','compaction','small_model']) assert.equal(config[key], undefined);
  assert.equal(config.permission, undefined, 'OpenCode 2 replaced the v1 permission map');
  assert.equal(config.plugin, undefined, 'the v1 plugin hook no longer enforces anything');
});

test('OpenCode 2 confines the build agent to workspace tools and GameSmith MCP', () => {
  const config = buildConfig({mcp:'C:/fixture/mcp.mjs',prompt_path:'C:/fixture/prompt.md'});
  assert.equal(config.default_agent,'build');
  assert.deepEqual(config.plugins,['C:/fixture']);
  const rules = config.agents.build.permissions;
  assert.deepEqual(rules[0], {action:'*',resource:'*',effect:'deny'}, 'unknown tools stay hidden until the surface names them');
  assert.deepEqual(rules.filter(rule=>rule.resource==='*' && rule.effect==='allow').map(rule=>rule.action), ['read','glob','grep','edit','write','gamesmith_*']);
  for (const [action,resource] of [['edit','.git/*'],['edit','*/.git/*'],['write','.git/*'],['write','*/.git/*']]) assert.ok(rules.some(rule=>rule.action===action && rule.resource===resource && rule.effect==='deny'), action+' '+resource);
  assert.deepEqual(rules.at(-1), {action:'gamesmith_*',resource:'*',effect:'allow'});
  assert.deepEqual(config.instructions, ['C:/fixture/prompt.md']);
  assert.deepEqual(config.mcp.servers.gamesmith, {type:'local',command:[process.execPath,'C:/fixture/mcp.mjs'],codemode:false});
  assert.equal(config.mcp.servers.gamesmith.environment, undefined, 'the MCP child inherits the adapter environment instead of copying it into the config');
});

test('OpenCode 2 keeps player settings while replacing the confined agent rules', () => {
  const existing = {model:'fixture/model',plugins:['player-plugin'],instructions:['global.md'],mcp:{timeout:{startup:5},servers:{other:{type:'local',command:['x']}}},agents:{plan:{permissions:[]}}};
  const merged = mergeConfig(existing,buildConfig({mcp:'C:/fixture/mcp.mjs',prompt_path:'C:/fixture/prompt.md'}),'opencode');
  assert.equal(merged.model,'fixture/model');
  assert.equal(merged.default_agent,'build');
  assert.deepEqual(merged.plugins,['player-plugin','C:/fixture']);
  assert.deepEqual(merged.instructions,['global.md','C:/fixture/prompt.md']);
  assert.deepEqual(Object.keys(merged.mcp.servers).sort(),['gamesmith','other']);
  assert.equal(merged.mcp.timeout.startup,5);
  assert.deepEqual(merged.agents.plan,{permissions:[]});
  assert.equal(merged.agents.build.permissions.at(-1).action,'gamesmith_*');
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
