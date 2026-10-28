import {readFileSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {isDeepStrictEqual} from 'node:util';
import {toolSpecs} from './workspace-tools.mjs';

export function nativeSettings(env=process.env) {
  const home=env.CLINE_DIR || join(env.HOME || env.USERPROFILE || homedir(),'.cline');
  const data=env.CLINE_DATA_DIR || join(home,'data');
  const providerPath=env.CLINE_PROVIDER_SETTINGS_PATH || join(data,'settings/providers.json');
  const globalPath=env.CLINE_GLOBAL_SETTINGS_PATH || join(data,'settings/global-settings.json');
  const saved=existsSync(providerPath) ? JSON.parse(readFileSync(providerPath,'utf8')) : {};
  const provider=env.CLINE_PROVIDER || saved.lastUsedProvider || 'cline';
  const settings=saved.providers?.[provider]?.settings || {};
  return {providerPath,globalPath,provider,model:env.CLINE_MODEL || settings.model,
    thinking:settings.reasoning?.enabled ? settings.reasoning.effort || 'medium' : 'none'};
}
const allowed=new Set(toolSpecs().map(t=>t.name.replace('gamesmith_','gamesmith__')));
function callName(call) {
  // Cline may omit ACP's optional name. Its native translator uses
  // buildToolTitle(toolName, input) and maps MCP tools to kind=other.
  // Never override a supplied programmatic identity with a display title.
  return call.name ?? (call.title || '').split(':')[0];
}
export class PermissionCalls {
  constructor(seen=new Set()){this.seen=seen;this.calls=new Map();}
  update(update={}) {
    if(!['tool_call','tool_call_update'].includes(update.sessionUpdate) || typeof update.toolCallId!=='string' || !update.toolCallId || update.toolCallId==='unknown')return;
    const id=update.toolCallId,previous=this.calls.get(id);
    if(previous){
      // Identity/input changes invalidate a pending call, rather than replacing
      // its authority. Normal status-only progress updates remain supported.
      for(const key of ['name','kind','rawInput'])if(update[key]!=null && !isDeepStrictEqual(update[key],previous[key]))previous.invalid=true;
      if(previous.name==null && update.title!=null && callName(update)!==callName(previous))previous.invalid=true;
      if(update.status!=null){previous.status=update.status;if(update.status!=='pending')previous.invalid=true;}
      return;
    }
    if(this.seen.has(id))return;
    this.seen.add(id);
    this.calls.set(id,{...update,invalid:update.status!=='pending'});
  }
  take(call={}) {
    if(!call || typeof call.toolCallId!=='string')return;
    const known=this.calls.get(call.toolCallId);
    if(!known || known.used)return;
    known.used=true; // Reserve before an asynchronous human reload approval.
    if(known.invalid || known.status!=='pending' || known.kind!=='other' || !allowed.has(callName(known)))return;
    for(const key of ['name','kind','rawInput'])if(call[key]!=null && !isDeepStrictEqual(call[key],known[key]))return;
    if(call.status!=null && call.status!=='pending')return;
    if(known.name==null && callName(call)!==callName(known))return;
    return callName(known);
  }
}
export function permissionResult(params,permitted) {
  const kind=permitted ? 'allow_once' : 'reject_once';
  const option=params.options?.find(o=>o.kind===kind);
  return {outcome:option ? {outcome:'selected',optionId:option.optionId} : {outcome:'cancelled'}};
}
export function normalizeUpdate(update={}) {
  if(['agent_message_chunk','agent_thought_chunk'].includes(update.sessionUpdate) && update.content?.type==='text')
    return [{type:'delta',kind:update.sessionUpdate==='agent_message_chunk' ? 'assistant' : 'thinking',text:update.content.text}];
  if(update.sessionUpdate==='tool_call')return [{type:'tool',name:(update.title || '').split(':')[0],description:update.title || ''}];
  if(update.sessionUpdate==='tool_call_update')return [{type:'status',text:'Cline is working...'}];
  return [];
}
