import {isDeepStrictEqual} from 'node:util';
import {toolSpecs} from './workspace-tools.mjs';
const allowed=new Set(toolSpecs().map(t=>t.name.slice(10)));
export function permissionResult(params,permitted){
 const option=params.options?.find(o=>o.kind===(permitted?'allow_once':'reject_once'));
 return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
// Kiro V2 announces host-resolved MCP identity on tool_call and repeats it
// on request_permission. Display titles and early tool_call_chunk are ignored.
export class PermissionCalls {
 constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
 update(u={}){
  if(!['tool_call','tool_call_update'].includes(u.sessionUpdate) || typeof u.toolCallId!=='string' || !u.toolCallId)return;
  let c=this.calls.get(u.toolCallId);
  if(!c){
   if(u.sessionUpdate!=='tool_call' || this.seen.has(u.toolCallId))return;
   this.seen.add(u.toolCallId);
   const identity=u._meta?.kiro;
   c={server:identity?.mcpServerName,name:identity?.toolName,kind:u.kind,input:structuredClone(u.rawInput),status:u.status || 'pending'};this.calls.set(u.toolCallId,c);
  }
  const identity=u._meta?.kiro;
  if(identity && (identity.mcpServerName!==c.server || identity.toolName!==c.name))c.invalid=true;
  if(u.rawInput!=null && !isDeepStrictEqual(u.rawInput,c.input))c.invalid=true;
  if(u.kind!=null && c.kind!=null && u.kind!==c.kind)c.invalid=true;
  if(u.status!=null)c.status=u.status;
  if(!['pending','in_progress'].includes(c.status))c.invalid=true;
 }
 take(p={}){
  const call=p.toolCall || {},c=this.calls.get(call.toolCallId);
  if(!c || c.used)return false;c.used=true;
  const identity=p._meta?.mcpToolIdentity;
  return !c.invalid && c.server==='gamesmith' && allowed.has(c.name) && identity?.serverName===c.server && identity.toolName===c.name &&
   (call.kind==null || call.kind===c.kind) && (call.status==null || call.status==='pending') && isDeepStrictEqual(call.rawInput,c.input);
 }
}
export function normalizeUpdate(u={},method='session/update'){
 if(method==='_kiro.dev/metadata')return Number.isFinite(u.contextUsagePercentage) && u.contextUsagePercentage>=0 && u.contextUsagePercentage<=100 ? [{type:'context',percent:u.contextUsagePercentage}] : [];
 if(['agent_message_chunk','agent_thought_chunk'].includes(u.sessionUpdate) && u.content?.type==='text')return [{type:'delta',kind:u.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text:u.content.text}];
 if(u.sessionUpdate==='tool_call')return [{type:'tool',name:u._meta?.kiro?.toolName || 'MCP tool',description:u.title || ''}];
 return [];
}
