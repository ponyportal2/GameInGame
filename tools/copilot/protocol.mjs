// Copilot MCP is authorized by exact startup/profile filters, never by titles.
export function permissionResult(params={}){
 const option=params.options?.find(o=>o.kind==='reject_once');
 return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
export function normalizeUpdate(u={}){
 if(['agent_message_chunk','agent_thought_chunk'].includes(u.sessionUpdate) && u.content?.type==='text'){
  // Copilot sends its complete startup information line without a terminator.
  // Keep that visible, but separate it from the subsequent assistant answer.
  const text=u.content.text+(u.sessionUpdate==='agent_message_chunk' && /^Info: Disabled tools: [a-z_]+(?:, [a-z_]+)*$/.test(u.content.text)?'\n\n':'');
  return [{type:'delta',kind:u.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text}];
 }
 if(u.sessionUpdate==='tool_call')return [{type:'tool',name:u.title || 'MCP tool',description:u.title || ''}];
 if(u.sessionUpdate==='usage_update' && Number.isFinite(u.used) && u.used>=0)return [{type:'context',tokens:u.used}];
 return [];
}
