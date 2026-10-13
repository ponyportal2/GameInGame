import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PermissionCalls,normalizeUpdate} from '../tools/kiro/protocol.mjs';
import {resolveExecutable} from '../tools/kiro/server.mjs';
import {mkdtempSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const update=(id='one')=>({sessionUpdate:'tool_call',toolCallId:id,title:'untrusted title',kind:'edit',rawInput:{path:'main.gd',content:'test'},_meta:{kiro:{mcpServerName:'gamesmith',toolName:'write'}}});
const request=(id='one')=>({toolCall:{toolCallId:id,rawInput:{path:'main.gd',content:'test'}},_meta:{mcpToolIdentity:{serverName:'gamesmith',toolName:'write'}}});
test('Kiro permission requires current call ID, matching structured MCP identity and arguments',()=>{
 const seen=new Set(),calls=new PermissionCalls(seen);
 assert.equal(calls.take(request()),false);
 calls.update(update());assert.equal(calls.take(request()),true);assert.equal(calls.take(request()),false);
 const next=new PermissionCalls(seen);next.update(update());assert.equal(next.take(request()),false);
 for(const change of [{kind:'execute'},{status:'completed'},{rawInput:{path:'other'}},{_meta:{kiro:{mcpServerName:'external',toolName:'write'}}}]){
  const c=new PermissionCalls();c.update(update());c.update({sessionUpdate:'tool_call_update',toolCallId:'one',...change});assert.equal(c.take(request()),false);
 }
 for(const spoof of [p=>delete p._meta,p=>p._meta.mcpToolIdentity.serverName='external',p=>p.toolCall.rawInput.path='other',p=>p.toolCall.toolCallId='stale']){
  const c=new PermissionCalls();c.update(update());const p=request();spoof(p);p.toolCall.title='@gamesmith/write';assert.equal(c.take(p),false);
 }
 const c=new PermissionCalls();c.update({...update(),_meta:{kiro:{toolName:'shell'}}});assert.equal(c.take(request()),false);
});
test('Kiro resolves its explicit executable independently of generic agent',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gs-kiro-resolver-')),file=join(dir,'kiro-cli.exe');writeFileSync(file,'fixture');
 assert.deepEqual(resolveExecutable(file,'win32'),{bin:file,prefix:[]});
});
test('native percentage is not fabricated token usage or cumulative metering',()=>{
 assert.deepEqual(normalizeUpdate({contextUsagePercentage:12.5,meteringUsage:[{value:9999}]},'_kiro.dev/metadata'),[{type:'context',percent:12.5}]);
 assert.deepEqual(normalizeUpdate({meteringUsage:[{value:9999}]},'_kiro.dev/metadata'),[]);
});
