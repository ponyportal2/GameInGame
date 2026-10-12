import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeSettings, permissionResult, normalizeUpdate} from '../tools/cline/protocol.mjs';

test('inherits native Cline selection without copying credentials',()=>{
  const data=mkdtempSync(join(tmpdir(),'gs-cline-'));mkdirSync(join(data,'settings'));
  writeFileSync(join(data,'settings/providers.json'),JSON.stringify({lastUsedProvider:'cline',providers:{cline:{settings:{model:'cline-free/test',auth:{accessToken:'SECRET'},reasoning:{enabled:true,effort:'xhigh'}}}}}));
  const settings=nativeSettings({CLINE_DATA_DIR:data});
  assert.equal(settings.model,'cline-free/test');assert.equal(settings.thinking,'xhigh');
  assert(!JSON.stringify(settings).includes('SECRET'));
});
test('only registered GameSmith MCP permissions can be allowed',()=>{
  const options=[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}];
  for(const title of ['gamesmith__write: main.gd','gamesmith__reload_game']) assert.equal(permissionResult({toolCall:{title},options},true).outcome.optionId,'yes');
  for(const title of ['shell: gamesmith__write','write_file','gamesmith__unknown','other__write']) assert.equal(permissionResult({toolCall:{title},options},true).outcome.optionId,'no');
  assert.equal(permissionResult({toolCall:{title:'gamesmith__write'},options},false).outcome.optionId,'no');
});
test('ACP updates preserve text and thought chunks',()=>{
  assert.deepEqual(normalizeUpdate({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'Hello'}}),[{type:'delta',kind:'assistant',text:'Hello'}]);
  assert.deepEqual(normalizeUpdate({sessionUpdate:'agent_thought_chunk',content:{type:'text',text:'Think'}}),[{type:'delta',kind:'thinking',text:'Think'}]);
  assert.deepEqual(normalizeUpdate({sessionUpdate:'user_message_chunk',content:{type:'text',text:'Replay'}}),[]);
});
