import {toolSpecs} from './workspace-tools.mjs';
export {normalizeUpdate,permissionResult} from './acp-updates.mjs';

const allowed=new Set(toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10)));
// CodeBuddy's ACP metadata carries the actual native tool identity. Display
// titles are not authority. IDs are single-use across the backend's turns.
export class PermissionCalls {
 constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
 update(u={}){
  if(!['tool_call','tool_call_update'].includes(u.sessionUpdate) || typeof u.toolCallId!=='string' || !u.toolCallId)return;
  const name=u._meta?.['codebuddy.ai/toolName'];
  let c=this.calls.get(u.toolCallId);
  if(!c){if(u.sessionUpdate!=='tool_call' || this.seen.has(u.toolCallId))return;this.seen.add(u.toolCallId);c={name,kind:u.kind,status:u.status};this.calls.set(u.toolCallId,c);}
  if(name!=null){if(c.name!=null && c.name!==name)c.invalid=true;c.name=name;}
  if(u.kind!=null && c.kind!==u.kind)c.invalid=true;
  if(u.status!=null){c.status=u.status;if(!['pending','in_progress'].includes(u.status))c.invalid=true;}
 }
 take(call={}){
  const c=this.calls.get(call.toolCallId);if(!c || c.used)return false;c.used=true;
  return !c.invalid && allowed.has(c.name) && c.name===call._meta?.['codebuddy.ai/toolName'] &&
   ['pending','in_progress'].includes(c.status) && (call.kind==null || call.kind===c.kind);
 }
}
