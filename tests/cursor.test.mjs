import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {PermissionCalls} from '../tools/cursor/protocol.mjs';
import {resolveExecutable} from '../tools/cursor/server.mjs';
function announced(calls,id='current',input={providerIdentifier:'gamesmith',toolName:'write',args:{path:'main.gd',content:'ok'}}){
  calls.update({sessionUpdate:'tool_call',toolCallId:id,title:'MCP: tool',kind:'other',status:'pending',rawInput:{}});
  calls.update({sessionUpdate:'tool_call_update',toolCallId:id,rawInput:input});
  calls.update({sessionUpdate:'tool_call_update',toolCallId:id,status:'in_progress'});
  return {toolCallId:id,title:'untrusted display title',kind:'other',status:'pending'};
}
test('permissions use structured provider/tool identity and a current unique call ID',()=>{
  const calls=new PermissionCalls();const call=announced(calls);
  assert.equal(calls.take(call),'gamesmith__write');
  assert.equal(calls.take(call),undefined);
  assert.equal(calls.take({toolCallId:'unknown',title:'gamesmith-write: write'}),undefined);
  const spoof=announced(calls,'spoof',{providerIdentifier:'native',toolName:'write',args:{}});
  spoof.title='gamesmith-write: write';assert.equal(calls.take(spoof),undefined);
});
test('conflicting identity, input, completed calls and cross-operation replay fail closed',()=>{
  for(const change of [{rawInput:{providerIdentifier:'gamesmith',toolName:'reload_game',args:{}}},{rawInput:{providerIdentifier:'gamesmith',toolName:'write',args:{path:'outside'}}},{status:'completed'},{name:'shell'}]){
    const calls=new PermissionCalls(),call=announced(calls);
    calls.update({sessionUpdate:'tool_call_update',toolCallId:call.toolCallId,...change});
    assert.equal(calls.take(call),undefined);
  }
  const seen=new Set(),first=new PermissionCalls(seen);announced(first);
  const next=new PermissionCalls(seen);assert.equal(next.take(announced(next)),undefined);
});
test('permission cannot bypass the structured announcement or change its arguments',()=>{
  const calls=new PermissionCalls();calls.update({sessionUpdate:'tool_call',toolCallId:'empty',kind:'other',status:'pending',rawInput:{},title:'gamesmith-write: write'});
  assert.equal(calls.take({toolCallId:'empty',title:'gamesmith-write: write'}),undefined);
  const call=announced(calls,'mismatch');call.rawInput={providerIdentifier:'gamesmith',toolName:'write',args:{}};
  assert.equal(calls.take(call),undefined);
});
test('Windows Cursor package uses its bundled Node, not another agent on PATH',()=>{
  const root=mkdtempSync(join(tmpdir(),'gs-cursor-resolver-'));mkdirSync(join(root,'versions','2026.10.01-test'),{recursive:true});
  const directory=join(root,'versions','2026.10.01-test');
  for(const path of [join(root,'cursor-agent.cmd'),join(directory,'node.exe'),join(directory,'index.js')])writeFileSync(path,'fixture');
  assert.deepEqual(resolveExecutable(join(root,'cursor-agent.cmd'),'win32'),{bin:join(directory,'node.exe'),prefix:[join(directory,'index.js')]});
  assert.deepEqual(resolveExecutable(join(directory,'index.js'),'win32'),{bin:join(directory,'node.exe'),prefix:[join(directory,'index.js')]});
});
