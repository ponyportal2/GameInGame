import {isDeepStrictEqual} from 'node:util';
import {toolSpecs} from './workspace-tools.mjs';
export function permissionResult(params,permitted){
  const option=params.options?.find(o=>o.kind===(permitted?'allow_once':'reject_once'));
  return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
}
const allowed=new Set(toolSpecs().map(t=>t.name.slice('gamesmith_'.length)));
export class PermissionCalls {
  constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
  update(update={}) {
    const id=update.toolCallId;
    if(!['tool_call','tool_call_update'].includes(update.sessionUpdate) || typeof id!=='string' || !id)return;
    let known=this.calls.get(id);
    if(!known){
      if(this.seen.has(id) || update.sessionUpdate!=='tool_call')return;
      this.seen.add(id);known={kind:update.kind,status:update.status};this.calls.set(id,known);
    }
    if(update.kind!=null && update.kind!==known.kind)known.invalid=true;
    if(update.name!=null)known.invalid=true; // This translator exposes identity in rawInput.
    if(update.rawInput && Object.keys(update.rawInput).length){
      if(known.input && !isDeepStrictEqual(update.rawInput,known.input))known.invalid=true;
      else if(!known.used)known.input=structuredClone(update.rawInput);
    }
    if(update.status!=null){known.status=update.status;if(!['pending','in_progress'].includes(update.status))known.invalid=true;}
  }
  take(call={}) {
    const known=this.calls.get(call?.toolCallId);
    if(!known || known.used)return;
    known.used=true;
    const input=known.input;
    if(known.invalid || known.kind!=='other' || !['pending','in_progress'].includes(known.status) || input?.providerIdentifier!=='gamesmith' || !allowed.has(input.toolName))return;
    if(call.name!=null || call.kind!=null && call.kind!==known.kind || call.rawInput!=null && !isDeepStrictEqual(call.rawInput,input) || call.status!=null && call.status!=='pending')return;
    return 'gamesmith__'+input.toolName;
  }
}
export function normalizeUpdate(update={}) {
  if(['agent_message_chunk','agent_thought_chunk'].includes(update.sessionUpdate) && update.content?.type==='text')return [{type:'delta',kind:update.sessionUpdate==='agent_message_chunk'?'assistant':'thinking',text:update.content.text}];
  if(update.sessionUpdate==='tool_call')return [{type:'tool',name:update.title || 'MCP tool',description:update.title || ''}];
  if(update.sessionUpdate==='tool_call_update')return [{type:'status',text:'Cursor is working...'}];
  return [];
}
