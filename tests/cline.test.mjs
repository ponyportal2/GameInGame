import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeSettings, permissionResult, normalizeUpdate, PermissionCalls} from '../tools/cline/protocol.mjs';

test('inherits native Cline selection without copying credentials',()=>{
  const data=mkdtempSync(join(tmpdir(),'gs-cline-'));mkdirSync(join(data,'settings'));
  writeFileSync(join(data,'settings/providers.json'),JSON.stringify({lastUsedProvider:'cline',providers:{cline:{settings:{model:'cline-free/test',auth:{accessToken:'SECRET'},reasoning:{enabled:true,effort:'xhigh'}}}}}));
  const settings=nativeSettings({CLINE_DATA_DIR:data});
  assert.equal(settings.model,'cline-free/test');assert.equal(settings.thinking,'xhigh');
  assert(!JSON.stringify(settings).includes('SECRET'));
});
test('permission requires an announced, single-use GameSmith call identity',()=>{
  const options=[{optionId:'yes',kind:'allow_once'},{optionId:'no',kind:'reject_once'}];
  const seen=new Set(), calls=new PermissionCalls(seen);
  const call={toolCallId:'write-1',title:'gamesmith__write: main.gd',kind:'other',status:'pending',rawInput:{path:'main.gd',content:'test'}};
  const decide=toolCall=>permissionResult({options},!!calls.take(toolCall)).outcome.optionId;
  assert.equal(decide(call),'no'); // A convincing title alone cannot authorize.
  calls.update({sessionUpdate:'tool_call',...call});
  assert.equal(decide({...call,toolCallId:'unknown'}),'no');
  assert.equal(decide(call),'yes');
  assert.equal(decide(call),'no');
  const nextTurn=new PermissionCalls(seen);
  nextTurn.update({sessionUpdate:'tool_call',...call});
  assert.equal(nextTurn.take(call),undefined); // Session IDs cannot be replayed next turn.
});
test('native kinds and conflicting structured identities cannot hide behind MCP titles',()=>{
  for(const changes of [{kind:'execute'},{kind:'edit'},{kind:'read'},{name:'run_commands'},{name:'other__write'},{title:'gamesmith__unknown'}]){
    const calls=new PermissionCalls(),call={toolCallId:'spoof',title:'gamesmith__write',kind:'other',status:'pending',rawInput:{},...changes};
    calls.update({sessionUpdate:'tool_call',...call});
    assert.equal(calls.take(call),undefined);
  }
  const calls=new PermissionCalls(),call={toolCallId:'structured',name:'gamesmith__write',title:'Write game',kind:'other',status:'pending',rawInput:{path:'main.gd'}};
  calls.update({sessionUpdate:'tool_call',...call});
  assert.equal(calls.take({...call,name:'run_commands'}),undefined);
  const valid=new PermissionCalls();valid.update({sessionUpdate:'tool_call',...call});
  assert.equal(valid.take({...call,title:'A changed display title'}),'gamesmith__write');
  assert.equal(valid.take(null),undefined);
});
test('Cline legacy pending updates work, but changed inputs and completed calls do not',()=>{
  const call={toolCallId:'legacy',title:'gamesmith__reload_game',kind:'other',status:'pending',rawInput:{}};
  const calls=new PermissionCalls();calls.update({sessionUpdate:'tool_call_update',...call});
  assert.equal(calls.take({...call,rawInput:{unexpected:true}}),undefined);
  const complete=new PermissionCalls();complete.update({sessionUpdate:'tool_call',...call});
  complete.update({sessionUpdate:'tool_call_update',toolCallId:call.toolCallId,status:'completed'});
  complete.update({sessionUpdate:'tool_call_update',...call});
  assert.equal(complete.take(call),undefined);
  const valid=new PermissionCalls();valid.update({sessionUpdate:'tool_call_update',...call});
  assert.equal(valid.take(call),'gamesmith__reload_game');
});
test('ACP updates preserve text and thought chunks',()=>{
  assert.deepEqual(normalizeUpdate({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'Hello'}}),[{type:'delta',kind:'assistant',text:'Hello'}]);
  assert.deepEqual(normalizeUpdate({sessionUpdate:'agent_thought_chunk',content:{type:'text',text:'Think'}}),[{type:'delta',kind:'thinking',text:'Think'}]);
  assert.deepEqual(normalizeUpdate({sessionUpdate:'user_message_chunk',content:{type:'text',text:'Replay'}}),[]);
});
