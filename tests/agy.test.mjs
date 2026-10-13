import {test} from 'node:test';
import assert from 'node:assert/strict';
import {permissionDecision,normalizeRecord,reconcileText} from '../tools/agy/protocol.mjs';

test('AGY permission uses native identity, server and current conversation; titles never authorize',()=>{
  const state={active:true,session:'session'};
  const call={conversationId:'session',toolCall:{name:'call_mcp_tool',args:{ServerName:'gamesmith',ToolName:'write',Arguments:{path:'main.gd',content:'ok'}}}};
  assert.equal(permissionDecision(call,state).decision,'auto_approve');
  for(const bad of [
    {...call,conversationId:'old'},
    {...call,toolCall:{name:'run_command',title:'gamesmith__write',args:call.toolCall.args}},
    {...call,toolCall:{...call.toolCall,args:{...call.toolCall.args,ServerName:'external'}}},
    {...call,toolCall:{...call.toolCall,args:{...call.toolCall.args,ToolName:'unknown'}}},
    {...call,toolCall:{...call.toolCall,args:{...call.toolCall.args,Arguments:'not an object'}}},
  ])assert.equal(permissionDecision(bad,state).decision,'deny');
  assert.equal(permissionDecision(call,{...state,active:false}).decision,'deny');
  assert.equal(permissionDecision({...call,toolCall:{name:'ask_permission',args:{}}},state).decision,'deny');
});
test('AGY streaming handles deltas and canonical final text without treating cumulative usage as context',()=>{
  assert.deepEqual(normalizeRecord({event:'step_update',step_update:{step_type:'agent_response',text_delta:'hello'}}),[{type:'delta',kind:'assistant',text:'hello'}]);
  assert.deepEqual(normalizeRecord({event:'result',result:{usage:{total_tokens:999999}}}),[]);
  assert.deepEqual(reconcileText('hello','hello world'),{text:'hello world',suffix:' world',corrected:false});
  assert.deepEqual(reconcileText('wrong','right'),{text:'right',suffix:'',corrected:true});
});
test('AGY native tool steps report activity even when only the final snapshot arrives',()=>{
  for(const state of ['ACTIVE','DONE'])assert.deepEqual(normalizeRecord({event:'step_update',step_update:{step_type:'tool',step_index:4,state,tool_name:'call_mcp_tool',tool_info:{name:'call_mcp_tool',parameters:{ServerName:'gamesmith',ToolName:'write'}}}}),[{type:'tool',name:'write',description:''}]);
});
