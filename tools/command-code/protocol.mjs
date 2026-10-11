export function buildArguments(config, prompt) {
  const args = ['--print', prompt, '--output-format', 'json', '--trust', '--yolo',
    '--skip-onboarding', '--no-auto-update', '--no-skills', '--mod', config.mod, '--name', config.name];
  if (config.session) args.push('--session', config.session);
  return args;
}

export function normalizeFrame(frame) {
  if (frame.type === 'result') {
    const ok = frame.subtype === 'success' && !['permission_denied', 'interrupted', 'max_turns'].includes(frame.stopReason);
    return [{type:'complete', ok, text:frame.finalText || '', session:frame.sessionId || '',
      error:ok ? '' : frame.error || `Command-code stopped: ${frame.stopReason || frame.subtype}`}];
  }
  const e = frame.type === 'event' ? frame.event : null;
  if (!e) return [];
  if (e.type === 'model_request_end') {
    const usage = e.usage || {};
    const tokens = ['inputTokens','cacheReadTokens','cacheWriteTokens','outputTokens'].reduce((sum,key) => sum + Math.max(0,Number(usage[key]) || 0),0);
    return tokens > 0 ? [{type:'context',tokens}] : [];
  }
  if (e.type === 'compaction_outcome' && e.outcome === 'summarized') return [{type:'context',tokens:null}];
  if (e.type === 'text_delta' || e.type === 'thinking_delta') return [{type:'delta',kind:e.type === 'text_delta' ? 'assistant' : 'thinking',text:e.delta || ''}];
  if (e.type === 'tool_running') return [{type:'tool',name:e.toolName,description:e.description || ''}];
  if (['tool_completed','tool_errored','model_request_start'].includes(e.type)) return [{type:'status',text:'Command-code is working…'}];
  if (e.type === 'run_start') return [{type:'session',session:e.sessionId || ''}];
  if (e.type === 'message_end') return [{type:'stream_end'}];
  if (e.type === 'compaction_start') return [{type:'status',text:'Command-code is compacting context…'}];
  if (e.type === 'compaction_done') return [{type:'status',text:'Command-code is working…'}];
  if (e.type === 'mod_error') return [{type:'integration_error',error:`Command-code mod ${e.modId || ''} ${e.hook || ''}: ${e.error || 'failed'}`}];
  return [];
}
