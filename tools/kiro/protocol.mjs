import {isDeepStrictEqual} from 'node:util';
import {toolSpecs} from './workspace-tools.mjs';
const allowed=new Set(toolSpecs().map(t=>t.name.slice(10)));
export function permissionResult(params,permitted){
 const option=params.options?.find(o=>o.kind===(permitted?'allow_once':'reject_once'));
 return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
// Kiro V3 announces a GameSmith tool as serverName plus a namespaced tool_id.
// The permission request repeats the same identity and the call ID; display
// titles and early tool_call_chunk are ignored.
function announced(u={}){
 const server=u._meta?.kiro?.serverName,id=u.rawInput?.tool_id;
 if(typeof server!=='string' || !server)return;
 if(typeof id!=='string')return {server,name:''};
 const parts=id.split('::');
 return parts.length===2 && parts[0]===server && parts[1] ? {server,name:parts[1]} : {server,name:''};
}
export class PermissionCalls {
 constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
 update(u={}){
  if(!['tool_call','tool_call_update'].includes(u.sessionUpdate) || typeof u.toolCallId!=='string' || !u.toolCallId)return;
  let c=this.calls.get(u.toolCallId);
  if(!c){
   if(u.sessionUpdate!=='tool_call' || this.seen.has(u.toolCallId))return;
   this.seen.add(u.toolCallId);
   const identity=announced(u);
   c={server:identity?.server,name:identity?.name,kind:u.kind,input:structuredClone(u.rawInput),status:u.status || 'pending'};this.calls.set(u.toolCallId,c);
  }
  const identity=announced(u);
  if(identity && (identity.server!==c.server || identity.name!==c.name))c.invalid=true;
  if(u.rawInput!=null && !isDeepStrictEqual(u.rawInput,c.input))c.invalid=true;
  if(u.kind!=null && c.kind!=null && u.kind!==c.kind)c.invalid=true;
  if(u.status!=null)c.status=u.status;
  if(!['pending','in_progress'].includes(c.status))c.invalid=true;
 }
 take(p={}){
  const call=p.toolCall || {},c=this.calls.get(call.toolCallId);
  if(!c || c.used)return false;c.used=true;
  const kiro=p._meta?.kiro,identity=kiro?.mcpTool?.identity;
  return !c.invalid && c.server==='gamesmith' && allowed.has(c.name) && typeof kiro?.toolId==='string' &&
   identity?.serverName===c.server && identity.toolName===c.name &&
   (call.kind==null || call.kind===c.kind) && (call.status==null || call.status==='pending') && (call.rawInput==null || isDeepStrictEqual(call.rawInput,c.input));
 }
}
export function normalizeUpdate(u={}){
 if(u.sessionUpdate==='session_info_update'){
  const kiro=u._meta?.kiro,percent=kiro?.usagePercentage;
  return kiro?.kind==='context_usage' && Number.isFinite(percent) && percent>=0 && percent<=100 ? [{type:'context',percent}] : [];
 }
 if(['agent_message_chunk','agent_thought_chunk'].includes(u.sessionUpdate) && u.content?.type==='text')return [{type:'delta',kind:u.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text:u.content.text}];
 if(u.sessionUpdate==='tool_call')return [{type:'tool',name:announced(u)?.name || 'MCP tool',description:u.title || ''}];
 return [];
}
