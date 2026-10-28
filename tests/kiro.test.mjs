import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PermissionCalls,normalizeUpdate} from '../tools/kiro/protocol.mjs';
import {resolveExecutable} from '../tools/kiro/server.mjs';
import {mkdtempSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const update=(id='one')=>({sessionUpdate:'tool_call',toolCallId:id,title:'untrusted title',kind:'other',rawInput:{tool_id:'gamesmith::write',arguments:{path:'main.gd'}},_meta:{kiro:{serverName:'gamesmith'}}});
const request=(id='one')=>({toolCall:{toolCallId:id},_meta:{kiro:{toolId:'mcp_gamesmith_write',mcpTool:{identity:{serverName:'gamesmith',toolName:'write'}}}}});
test('Kiro permission requires current call ID, matching structured MCP identity and arguments',()=>{
 const seen=new Set(),calls=new PermissionCalls(seen);
 assert.equal(calls.take(request()),false);
 calls.update(update());assert.equal(calls.take(request()),true);assert.equal(calls.take(request()),false);
 const next=new PermissionCalls(seen);next.update(update());assert.equal(next.take(request()),false);
 for(const change of [{kind:'execute'},{status:'completed'},{rawInput:{tool_id:'gamesmith::write',arguments:{path:'other'}}},{_meta:{kiro:{serverName:'external'}}},{rawInput:{tool_id:'external::write',arguments:{path:'main.gd'}}}]){
  const c=new PermissionCalls();c.update(update());c.update({sessionUpdate:'tool_call_update',toolCallId:'one',...change});assert.equal(c.take(request()),false);
 }
 for(const spoof of [p=>delete p._meta,p=>p._meta.kiro.mcpTool.identity.serverName='external',p=>p._meta.kiro.toolId=42,p=>p.toolCall.rawInput={tool_id:'gamesmith::write',arguments:{path:'other'}},p=>p.toolCall.toolCallId='stale',p=>p.toolCall.kind='execute']){
  const c=new PermissionCalls();c.update(update());const p=request();spoof(p);p.toolCall.title='@gamesmith/write';assert.equal(c.take(p),false);
 }
 const c=new PermissionCalls();c.update({...update(),_meta:{kiro:{serverName:'external'}}});assert.equal(c.take(request()),false);
 const missing=new PermissionCalls();missing.update({...update(),_meta:undefined});assert.equal(missing.take(request()),false);
});
test('Kiro resolves its explicit executable independently of generic agent',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gs-kiro-resolver-')),file=join(dir,'kiro-cli.exe');writeFileSync(file,'fixture');
 assert.deepEqual(resolveExecutable(file,'win32'),{bin:file,prefix:[]});
});
test('native percentage is not fabricated token usage or cumulative metering',()=>{
 assert.deepEqual(normalizeUpdate({sessionUpdate:'session_info_update',_meta:{kiro:{kind:'context_usage',usagePercentage:12.5,breakdown:{tools:{tokens:9999}}}}}),[{type:'context',percent:12.5}]);
 assert.deepEqual(normalizeUpdate({sessionUpdate:'session_info_update',_meta:{kiro:{kind:'focus_update',usagePercentage:12.5}}}),[]);
 assert.deepEqual(normalizeUpdate({sessionUpdate:'session_info_update',_meta:{kiro:{kind:'context_usage',usagePercentage:120}}}),[]);
 assert.deepEqual(normalizeUpdate({sessionUpdate:'session_info_update'}),[]);
});
