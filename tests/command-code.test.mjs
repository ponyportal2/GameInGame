import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, copyFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

test('mod exposes host tools and guards native absolute paths without taking over model policy', async () => {
  const dir = await mkdtemp(join(tmpdir(),'gamesmith-mod-test-'));
  await copyFile(new URL('../tools/command-code/gamesmith.ts',import.meta.url),join(dir,'gamesmith.ts'));
  await copyFile(new URL('../tools/command-code/policy.mjs',import.meta.url),join(dir,'policy.mjs'));
  await copyFile(new URL('../tools/pi/workspace-paths.mjs',import.meta.url),join(dir,'workspace-paths.mjs'));
  const workspace = join(dir,'workspace');
  await mkdir(workspace);
  const prompt = join(dir,'prompt.md');
  await writeFile(prompt,'Stable game instructions');
  const oldPrompt = process.env.GAMESMITH_PROMPT_PATH;
  const oldBridge = process.env.GAMESMITH_HOST_BRIDGE_DIR;
  process.env.GAMESMITH_PROMPT_PATH = prompt;
  process.env.GAMESMITH_HOST_BRIDGE_DIR = dir;
  const tools = [];
  let hooks;
  let active;
  const cmd = {cwd:workspace,addTool:tool => tools.push(tool),hooks:value => {hooks=value;},
    getAllTools:() => ['read_file','read_directory','write_file','edit_file','grep','glob','shell_command','powershell','agent',...tools.map(t=>t.schema.name)],
    setActiveTools:names => {active=names;}};
  try {
    const mod = await import(pathToFileURL(join(dir,'gamesmith.ts')));
    await mod.default(cmd);
    assert.ok(active.includes('write_file') && active.includes('reload_game') && active.includes('start_test_game'));
    for (const tool of tools) assert.ok(Array.isArray(tool.schema.input_schema.required), `${tool.schema.name} has required fields for Command-code validation`);
    assert.ok(!active.includes('shell_command') && !active.includes('powershell') && !active.includes('agent'));
    assert.equal(await hooks.appendSystemPrompt(), 'Stable game instructions');
    assert.equal(await hooks.beforeToolCall({toolName:'write_file',input:{file_path:join(workspace,'main.gd')}}),undefined);
    assert.equal((await hooks.beforeToolCall({toolName:'write_file',input:{file_path:join(dir,'outside.gd')}})).block,true);
    assert.equal((await hooks.beforeToolCall({toolName:'write_file',input:{file_path:join(workspace,'.git','config')}})).block,true);
    assert.equal((await hooks.beforeToolCall({toolName:'shell_command',input:{}})).block,true);
    assert.equal(await hooks.beforeToolCall({toolName:'read_file',input:{paths:[join(workspace,'main.gd')]}}),undefined);
    assert.equal((await hooks.beforeToolCall({toolName:'read_file',input:{paths:[join(dir,'outside')]}})).block,true);
    assert.equal(hooks.prepareNextTurn,undefined);
    assert.equal(hooks.shouldStopAfterTurn,undefined);
    const resultPending = tools.find(tool => tool.schema.name === 'reload_game').run({input:{}});
    let request;
    while (!request) {
      request = (await readdir(dir)).find(name => /^request-.*\.json$/.test(name));
      if (!request) await new Promise(resolve => setTimeout(resolve, 5));
    }
    await writeFile(join(dir,request.replace('request-','response-')), JSON.stringify({ok:false,error:'startup failed',diagnostics:{errors:['bad property']}}));
    const failed = await resultPending;
    assert.equal(failed.ok,false,'host failure remains a failed native tool result');
    assert.equal(JSON.parse(failed.error).diagnostics.errors[0],'bad property');
  } finally {
    if (oldPrompt === undefined) delete process.env.GAMESMITH_PROMPT_PATH;
    else process.env.GAMESMITH_PROMPT_PATH = oldPrompt;
    if (oldBridge === undefined) delete process.env.GAMESMITH_HOST_BRIDGE_DIR;
    else process.env.GAMESMITH_HOST_BRIDGE_DIR = oldBridge;
  }
});
