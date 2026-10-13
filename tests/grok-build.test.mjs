import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PermissionCalls} from '../tools/grok-build/protocol.mjs';
import {resolveExecutable} from '../tools/grok-build/server.mjs';

function announce(calls,id='current',input={variant:'MCPTool',tool_name:'gamesmith__write',tool_input:{path:'main.gd',content:'ok'}}){
  calls.update({sessionUpdate:'tool_call',toolCallId:id,title:'arbitrary display text',kind:'other',status:'pending',rawInput:input,_meta:{'x.ai/tool':{name:'use_tool',kind:'use_tool',namespace:'grok_build'}}});
  return {toolCallId:id,kind:'other',status:'pending',rawInput:input,_meta:{'x.ai/tool':{name:'use_tool',kind:'use_tool',namespace:'grok_build'}}};
}
test('Grok permissions bind the current call to structured GameSmith MCP identity',()=>{
  const calls=new PermissionCalls(),call=announce(calls);
  assert.equal(calls.take(call),'gamesmith__write');
  assert.equal(calls.take(call),undefined);
  assert.equal(calls.take({toolCallId:'missing',title:'gamesmith__write'}),undefined);
  for(const input of [{variant:'Bash',tool_name:'gamesmith__write',tool_input:{}},{variant:'MCPTool',tool_name:'external__write',tool_input:{}},{variant:'UseTool',tool_name:'gamesmith__write',tool_input_file:'native.txt'}]){
    const tracker=new PermissionCalls();assert.equal(tracker.take(announce(tracker,'spoof',input)),undefined);
  }
});
test('Grok rejects changed arguments, completed calls and replay across operations',()=>{
  const seen=new Set(),calls=new PermissionCalls(seen),call=announce(calls);
  calls.update({sessionUpdate:'tool_call_update',toolCallId:'current',rawInput:{...call.rawInput,tool_input:{path:'outside'}}});
  assert.equal(calls.take(call),undefined);
  const next=new PermissionCalls(seen);assert.equal(next.take(announce(next)),undefined);
  const done=new PermissionCalls(),completed=announce(done);done.update({sessionUpdate:'tool_call_update',toolCallId:'current',status:'completed'});assert.equal(done.take(completed),undefined);
});
test('Grok discovery uses grok, never the ambiguous agent command',()=>{
  const prior=process.env.GAMESMITH_GROK_BUILD_BIN;delete process.env.GAMESMITH_GROK_BUILD_BIN;
  try {assert.equal(resolveExecutable('', 'linux').bin,'grok');}
  finally{if(prior!==undefined)process.env.GAMESMITH_GROK_BUILD_BIN=prior;}
});

test('Grok eager announcement can acquire kind and variant without changing tool arguments',()=>{
 const calls=new PermissionCalls();const input={tool_name:'gamesmith__write',tool_input:{path:'main.gd',content:'ok'}};
 const meta={'x.ai/tool':{name:'use_tool',kind:'use_tool',namespace:'grok_build'}};
 calls.update({sessionUpdate:'tool_call',toolCallId:'eager',title:'use_tool',rawInput:input,_meta:meta});
 calls.update({sessionUpdate:'tool_call_update',toolCallId:'eager',kind:'other',rawInput:{variant:'UseTool',...input},_meta:meta});
 assert.equal(calls.take({toolCallId:'eager',kind:'other',rawInput:{variant:'UseTool',...input},_meta:meta}),'gamesmith__write');
});
