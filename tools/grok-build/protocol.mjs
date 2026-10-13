import {isDeepStrictEqual} from 'node:util';
import {toolSpecs} from './workspace-tools.mjs';
export function permissionResult(params,permitted){
  const option=params.options?.find(o=>o.kind===(permitted?'allow_once':'reject_once'));
  return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
const allowed=new Set(toolSpecs().map(t=>t.name.slice('gamesmith_'.length)));
function identity(call){return call?._meta?.['x.ai/tool'];}
function input(call){
 const raw=call.rawInput;
 if(!raw || typeof raw!=='object' || raw.variant!=null && !['UseTool','MCPTool'].includes(raw.variant) || !raw.tool_input || typeof raw.tool_input!=='object' || Array.isArray(raw.tool_input) || raw.file!=null || raw.tool_input_file!=null)return;
 return {tool_name:raw.tool_name,tool_input:raw.tool_input};
}
function isMcp(identity){return identity?.namespace==='grok_build' && identity.name==='use_tool' && identity.kind==='use_tool';}
export class PermissionCalls {
 constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
 update(update={}){
  const id=update.toolCallId;
  if(!['tool_call','tool_call_update'].includes(update.sessionUpdate) || typeof id!=='string' || !id)return;
  let known=this.calls.get(id);
  if(!known){if(this.seen.has(id) || update.sessionUpdate!=='tool_call')return;this.seen.add(id);known={status:'pending'};this.calls.set(id,known);}
  if(update.name!=null)known.invalid=true;
  if(update.kind!=null){if(known.kind!=null && known.kind!==update.kind)known.invalid=true;known.kind=update.kind;}
  if(identity(update)!=null){if(known.identity && !isDeepStrictEqual(known.identity,identity(update)))known.invalid=true;else known.identity=structuredClone(identity(update));}
  if(update.rawInput!=null){const parsed=input(update);if(!parsed || known.input && !isDeepStrictEqual(known.input,parsed))known.invalid=true;else if(!known.used)known.input=structuredClone(parsed);}
  if(update.status!=null){known.status=update.status;if(!['pending','in_progress'].includes(update.status))known.invalid=true;}
 }
 take(call={}){
  const known=this.calls.get(call?.toolCallId);if(!known || known.used)return;known.used=true;
  const name=known.input?.tool_name;
  if(known.invalid || known.kind!=='other' || !isMcp(known.identity) || !['pending','in_progress'].includes(known.status) || typeof name!=='string' || !name.startsWith('gamesmith__') || !allowed.has(name.slice('gamesmith__'.length)))return;
  if(call.name!=null || call.kind!=null && call.kind!==known.kind || call.status!=null && !['pending','in_progress'].includes(call.status) || call.rawInput!=null && !isDeepStrictEqual(input(call),known.input) || identity(call)!=null && !isDeepStrictEqual(identity(call),known.identity))return;
  return name;
 }
}
export function normalizeUpdate(update={}) {
  if(['agent_message_chunk','agent_thought_chunk'].includes(update.sessionUpdate) && update.content?.type==='text')return [{type:'delta',kind:update.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text:update.content.text}];
  if(update.sessionUpdate==='tool_call')return [{type:'tool',name:update.title || 'MCP tool',description:update.title || ''}];
  if(update.sessionUpdate==='tool_call_update')return [{type:'status',text:'Grok Build is working...'}];
  return [];
}
