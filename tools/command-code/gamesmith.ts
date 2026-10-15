import { readFile, writeFile, rename, rm } from 'node:fs/promises';
import { join, relative, isAbsolute } from 'node:path';
import { randomUUID } from 'node:crypto';
import { workspacePath } from './workspace-paths.mjs';
import { POLICY_VERSION, TOOL_NAMES } from './policy.mjs';
import { hostTools, toolContent } from './host-tools.mjs';

export async function callHost(command, args, signal) {
  const directory = process.env.GAMESMITH_HOST_BRIDGE_DIR;
  const id = randomUUID();
  const request = join(directory!, `request-${id}.json`);
  const response = join(directory!, `response-${id}.json`);
  await writeFile(request + '.tmp', JSON.stringify({id,command,args}));
  await rename(request + '.tmp', request);
  while (!signal?.aborted) {
    try {
      const result = JSON.parse(await readFile(response, 'utf8'));
      await rm(response);
      return result;
    } catch (error: any) { if (error.code !== 'ENOENT') throw error; }
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('GameSmith tool cancelled.');
}

export default async function (cmd) {
  const prompt = await readFile(process.env.GAMESMITH_PROMPT_PATH!, 'utf8');
  const tools = {
    blender: hostTools.blender,
    reload_game: {description:'After successful headless testing of the current edits, request loading the game before handoff. Waits for player approval unless auto-approval is enabled.',properties:{}},
    read_runtime_log: {description:'Read live game errors and runtime logs.',properties:{since_sequence:{type:'integer'},limit:{type:'integer'}}},
    start_test_game: {description:'Start a separate Godot game test.',properties:{mode:{type:'string',enum:['headless','rendered']}}},
    read_test_log: {description:'Read separate game test status and logs.',properties:{run_id:{type:'string'},limit:{type:'integer'},since_sequence:{type:'integer'}}},
    stop_test_game: {description:'Stop a separate test gracefully.',properties:{run_id:{type:'string'}}},
    test_game_action: {description:'Inspect or interact with a test game; poll action IDs for results.',properties:{run_id:{type:'string'},action:{type:'string',enum:['inspect','call','input','screenshot','poll']},action_id:{type:'string'},path:{type:'string'},properties:{type:'array',items:{type:'string'}},method:{type:'string'},arguments:{type:'array',items:{}},pressed:{type:'boolean'},input_action:{type:'string'}}},
    git_status: {description:'Show workspace Git status.',properties:{}},
    git_diff: {description:'Show workspace changes.',properties:{path:{type:'string'}}},
    git_log: {description:'Show workspace Git milestones.',properties:{limit:{type:'integer'}}},
    git_commit: {description:'Commit a coherent game milestone.',properties:{message:{type:'string'}}},
    delete_path: {description:'Delete a workspace path.',properties:{path:{type:'string'}}},
    move_path: {description:'Move a workspace path.',properties:{from:{type:'string'},to:{type:'string'}}},
  };
  for (const [name, tool] of Object.entries(tools)) cmd.addTool({
    schema:{name,description:tool.description,input_schema:{type:'object',properties:tool.properties,required:[]}},
    readOnly:['read_runtime_log','read_test_log','git_status','git_diff','git_log'].includes(name),
    run:async ({input,signal}) => {
      const result = await callHost(name,input,signal);
      if (result.ok === false) return {ok:false,error:JSON.stringify(result)};
      // ModApi uses native image blocks; MCP's data/mimeType shape is different.
      return {ok:true,content:toolContent(result).map(part => part.type === 'image'
        ? {type:'image',source:{type:'base64',media_type:part.mimeType,data:part.data}}
        : part)};
    },
  });
  const allowed = TOOL_NAMES;
  // 1.82.1 adds these discovery tools after constructing the mod registry.
  // Register deny-only entries so setActiveTools also hides the injected schemas.
  for (const name of ['search_tools', 'tool_search']) cmd.addTool({
    schema:{name,description:'Unavailable inside GameSmith.',input_schema:{type:'object',properties:{},required:[]}},
    readOnly:true,
    run:async () => ({ok:false,error:'Tool discovery is unavailable inside GameSmith.'}),
  });
  const activate = () => cmd.setActiveTools(cmd.getAllTools().filter(name => allowed.includes(name)));
  activate();
  cmd.hooks({
    appendSystemPrompt:() => prompt,
    onTurnStart:({state}) => { activate(); return state; },
    beforeToolCall:async event => {
      try {
        const {toolName,input} = event;
        if (!allowed.includes(toolName)) return {block:true,additionalContext:'This tool is unavailable inside GameSmith.'};
        if (!input || typeof input !== 'object' || Array.isArray(input))
          return {block:true,additionalContext:'Invalid GameSmith tool input.'};
        for (const key of ['absolute_path','file_path','path','from','to','target_directory']) if (typeof input[key] === 'string')
          await workspacePath(cmd.cwd,isAbsolute(input[key]) ? relative(cmd.cwd,input[key]) || '.' : input[key],{destructive:!['read_file','grep','glob','read_directory'].includes(toolName)});
        if (Array.isArray(input.paths)) for (const path of input.paths)
          await workspacePath(cmd.cwd,isAbsolute(path) ? relative(cmd.cwd,path) || '.' : path);
      } catch {
        // Native 1.82.1 continues execution after an uncaught mod-hook error.
        // Keep every guard operation inside this boundary, including decoding.
        return {block:true,additionalContext:'GameSmith workspace validation failed; the tool was blocked.'};
      }
    },
  });
  if (process.env.GAMESMITH_COMMAND_ACP === 'v1') {
    const nonce = process.env.GAMESMITH_POLICY_NONCE!;
    const ready = async (phase, names = []) => {
      const path = process.env.GAMESMITH_POLICY_READY!;
      await writeFile(path + '.tmp', JSON.stringify({policy:'gamesmith',version:POLICY_VERSION,nonce,phase,tools:names}));
      await rename(path + '.tmp', path);
    };
    cmd.addCommand({name:'gamesmith-ready-' + nonce,description:'Verify the private GameSmith integration without inference.',handler:async () => {
      activate();
      const names = cmd.getActiveTools();
      if (names.length !== allowed.length || new Set(names).size !== allowed.length || names.some(name => !allowed.includes(name)))
        throw new Error('Command-code did not install the exact GameSmith tool allowlist.');
      await ready('session', names);
      return {message:'GameSmith policy ready: ' + nonce};
    }});
    for (const type of ['compaction_start','compaction_outcome','mod_error'])
      cmd.on(type,event => process.stdout.write(JSON.stringify({type:'gamesmith_policy',nonce,event}) + '\n'));
    await ready('loaded');
  }
}
