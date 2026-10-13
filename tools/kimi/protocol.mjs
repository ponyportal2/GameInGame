export function permissionResult(params,permitted){
 const option=params.options?.find(o=>o.kind===(permitted?'allow_once':'reject_once'));
 return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
// This is call ownership, not tool identity. Kimi's native agent profile
// enforces the exact GameSmith MCP allowlist before execution.
export class PermissionCalls {
 constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
 update(u={}){
  if(!['tool_call','tool_call_update'].includes(u.sessionUpdate) || typeof u.toolCallId!=='string' || !u.toolCallId)return;
  let c=this.calls.get(u.toolCallId);
  if(!c){if(u.sessionUpdate!=='tool_call' || this.seen.has(u.toolCallId))return;this.seen.add(u.toolCallId);c={kind:u.kind,status:u.status};this.calls.set(u.toolCallId,c);}
  if(u.kind!=null && u.kind!==c.kind)c.invalid=true;
  if(u.status!=null){c.status=u.status;if(!['pending','in_progress'].includes(u.status))c.invalid=true;}
 }
 take(call={}){
  const c=this.calls.get(call.toolCallId);if(!c || c.used)return false;c.used=true;
  return !c.invalid && c.kind==='other' && ['pending','in_progress'].includes(c.status) && (call.kind==null || call.kind===c.kind) && (call.status==null || call.status==='pending');
 }
}
export function normalizeUpdate(u={}){
 if(['agent_message_chunk','agent_thought_chunk'].includes(u.sessionUpdate) && u.content?.type==='text')return [{type:'delta',kind:u.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text:u.content.text}];
 if(u.sessionUpdate==='tool_call')return [{type:'tool',name:u.title || 'MCP tool',description:u.title || ''}];
 if(u.sessionUpdate==='usage_update' && Number.isFinite(u.used) && u.used>=0)return [{type:'context',tokens:u.used,context_window:u.size}];
 return [];
}
