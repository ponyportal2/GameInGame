import { pathToFileURL } from 'node:url';

export function buildArguments(config, prompt) {
  const args = ['run', '--format', 'json', '--thinking', '--auto', '--title', config.name];
  if (config.session) args.push('--session', config.session);
  args.push('--', prompt);
  return args;
}

export function buildConfig(config) {
  return {
    plugin: [pathToFileURL(config.plugin).href],
    instructions: [config.prompt_path],
    permission: {'*':config.harness==='kilo' ? 'deny' : 'ask',read:'allow',write:'allow',edit:'allow',glob:'allow',grep:'allow',list:'allow',
      ...(config.harness==='kilo' ? {apply_patch:'allow'} : {}),
      bash:config.harness==='kilo' ? 'deny' : 'ask',external_directory:'deny', 'gamesmith_*':'allow'},
    mcp: {gamesmith: {type:'local',command:[process.execPath, config.mcp],enabled:true}},
  };
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
