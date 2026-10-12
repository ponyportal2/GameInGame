import {readFileSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
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
export function permissionResult(params,active) {
  const name=(params.toolCall?.title || '').split(':')[0];
  const kind=active && allowed.has(name) ? 'allow_once' : 'reject_once';
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
