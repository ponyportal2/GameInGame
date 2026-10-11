import test from 'node:test';
import assert from 'node:assert/strict';
import { buildArguments, normalizeFrame } from '../tools/command-code/protocol.mjs';
import { mkdtemp, copyFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

test('uses native configuration and explicit per-game resume', () => {
  const args = buildArguments({ mod: 'mod.ts', session: 'saved-id', name: 'game' }, 'hello');
  assert.deepEqual(args.slice(-2), ['--session', 'saved-id']);
  assert.ok(args.includes('--output-format'));
  for (const flag of ['--model', '--effort', '--config', '--max-turns', '--continue']) assert.ok(!args.includes(flag));
  assert.ok(args.includes('hello'));
});
test('streams text and thinking and ignores unfamiliar events', () => {
  assert.deepEqual(normalizeFrame({type:'event',event:{type:'text_delta',delta:'hi'}}), [{type:'delta',kind:'assistant',text:'hi'}]);
  assert.deepEqual(normalizeFrame({type:'event',event:{type:'thinking_delta',delta:'hmm'}}), [{type:'delta',kind:'thinking',text:'hmm'}]);
  assert.deepEqual(normalizeFrame({type:'event',event:{type:'future'}}), []);
});
test('completed and failed tools release stale running status for the next model call', () => {
  for (const type of ['tool_completed','tool_errored','model_request_start']) {
    assert.equal(normalizeFrame({type:'event',event:{type,toolName:'reload_game'}})[0]?.type, 'status');
    assert.match(normalizeFrame({type:'event',event:{type,toolName:'reload_game'}})[0].text, /working/);
  }
});
test('terminal errors and turn caps cannot masquerade as success', () => {
  assert.equal(normalizeFrame({type:'result',subtype:'max_turns',sessionId:'a',finalText:'partial'})[0].ok, false);
  assert.equal(normalizeFrame({type:'result',subtype:'error',error:'offline'})[0].error, 'offline');
  assert.equal(normalizeFrame({type:'result',subtype:'success',stopReason:'permission_denied'})[0].ok, false);
  assert.equal(normalizeFrame({type:'result',subtype:'success',stopReason:'end_turn',finalText:'done'})[0].ok, true);
});

test('mod exposes host tools and guards native absolute paths without taking over model policy', async () => {
  const dir = await mkdtemp(join(tmpdir(),'gamesmith-mod-test-'));
  await copyFile(new URL('../tools/command-code/gamesmith.ts',import.meta.url),join(dir,'gamesmith.ts'));
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
