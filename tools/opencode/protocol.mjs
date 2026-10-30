import { pathToFileURL } from 'node:url';
import { dirname } from 'node:path';

// OpenCode 2 exposes far more capability than GameSmith allows. The confined
// agent names the tools it may use and denies everything else, so a tool added
// by a later OpenCode release stays invisible until it is reviewed here.
const ALLOWED_ACTIONS = ['read','glob','grep','edit','write'];
const RESERVED_PATHS = ['.git/*','*/.git/*'];

export function buildArguments(config, prompt) {
  const args = ['run', '--format', 'json', '--thinking', '--auto', '--title', config.name];
  if (config.session) args.push('--session', config.session);
  args.push('--', prompt);
  return args;
}

export function buildConfig(config) {
  return config.harness === 'kilo' ? kiloConfig(config) : opencodeConfig(config);
}

function kiloConfig(config) {
  return {
    plugin: [pathToFileURL(config.plugin).href],
    instructions: [config.prompt_path],
    permission: {'*':'deny',read:'allow',write:'allow',edit:'allow',glob:'allow',grep:'allow',list:'allow',apply_patch:'allow',bash:'deny',external_directory:'deny', 'gamesmith_*':'allow'},
    mcp: {gamesmith: {type:'local',command:[process.execPath, config.mcp],enabled:true}},
  };
}

// OpenCode 2 applies agent permissions as an ordered rule list: the last rule
// matching an action and resource wins, and a `deny` on resource `*` also hides
// the tool from the model. The default-deny rule comes first, then the native
// file tools and the GameSmith MCP are allowed back, and the reserved-path rules
// run last so no allow can reopen the repository metadata. The MCP child inherits
// the adapter environment, which already carries the bridge directory and the
// Blender switch.
function opencodeConfig(config) {
  const allow = action => ({action,resource:'*',effect:'allow'});
  return {
    default_agent: 'build',
    plugins: [dirname(config.mcp)],
    agents: {build: {permissions: [
      {action:'*',resource:'*',effect:'deny'},
      ...ALLOWED_ACTIONS.map(allow),
      ...RESERVED_PATHS.flatMap(resource => [{action:'edit',resource,effect:'deny'},{action:'write',resource,effect:'deny'}]),
      {action:'gamesmith_*',resource:'*',effect:'allow'},
    ]}},
    instructions: [config.prompt_path],
    mcp: {servers: {gamesmith: {type:'local',command:[process.execPath,config.mcp],codemode:false}}},
  };
}

export function mergeConfig(existing, host, harness) {
  if (harness === 'kilo') return {...existing,...host,
    plugin: [...(existing.plugin || []),...host.plugin],
    instructions: [...(existing.instructions || []),...host.instructions],
    mcp: {...existing.mcp,...host.mcp}};
  return {...existing,...host,
    plugins: [...(existing.plugins || []),...host.plugins],
    agents: {...existing.agents,build: {...existing.agents?.build,...host.agents.build}},
    instructions: [...(existing.instructions || []),...host.instructions],
    mcp: {...existing.mcp,...host.mcp,servers: {...existing.mcp?.servers,...host.mcp.servers}}};
}

export function normalizeFrame(frame, label='OpenCode') {
  const records = frame.sessionID ? [{type:'session',session:frame.sessionID}] : [];
  const part = frame.part || {};
  if (frame.type === 'text') records.push({type:'delta',kind:'assistant',text:part.text || ''}, {type:'assistant_text',text:part.text || ''});
  if (frame.type === 'reasoning') records.push({type:'delta',kind:'thinking',text:part.text || ''});
  if (frame.type === 'step_start') records.push({type:'status',text:label+' is working...'});
  if (frame.type === 'tool_use') {
    records.push({type:'tool',name:part.tool || '',description:part.state?.title || part.state?.status || ''});
    if (['completed','error'].includes(part.state?.status)) records.push({type:'status',text:label+' is working...'});
  }
  if (frame.type === 'step_finish') {
    const t = part.tokens || {};
    const tokens = Number(t.total) || [t.input,t.output,t.reasoning,t.cache?.read,t.cache?.write].reduce((sum,v)=>sum+Math.max(0,Number(v)||0),0);
    if (tokens) records.push({type:'context',tokens});
    records.push({type:'stream_end'});
  }
  if (frame.type === 'error') records.push({type:'integration_error',error:frame.error?.data?.message || frame.error?.message || frame.error?.name || label+' request failed.'});
  return records;
}
