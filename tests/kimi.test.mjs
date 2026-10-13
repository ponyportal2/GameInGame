import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PermissionCalls,normalizeUpdate} from '../tools/kimi/protocol.mjs';
import {resolveExecutable} from '../tools/kimi/server.mjs';
import {mkdtempSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
test('native restricted-profile permissions require a current single-use call ID, never a title',()=>{
 const seen=new Set(),calls=new PermissionCalls(seen);
 assert.equal(calls.take({title:'mcp__gamesmith__write',toolCallId:'unknown'}),false);
 calls.update({sessionUpdate:'tool_call',toolCallId:'one',kind:'other',status:'pending',title:'untrusted'});
 assert.equal(calls.take({toolCallId:'one',title:'arbitrary display label'}),true);
 assert.equal(calls.take({toolCallId:'one'}),false);
 const next=new PermissionCalls(seen);next.update({sessionUpdate:'tool_call',toolCallId:'one',kind:'other',status:'pending'});
 assert.equal(next.take({toolCallId:'one'}),false);
 for(const change of [{kind:'execute'},{status:'completed'}]){
  const c=new PermissionCalls();c.update({sessionUpdate:'tool_call',toolCallId:'call',kind:'other',status:'pending'});
  c.update({sessionUpdate:'tool_call_update',toolCallId:'call',...change});assert.equal(c.take({toolCallId:'call'}),false);
 }
});
test('Kimi resolves its explicit executable independently of generic agent',()=>{
 const dir=mkdtempSync(join(tmpdir(),'gs-kimi-resolver-')),file=join(dir,'kimi.exe');writeFileSync(file,'fixture');
 assert.deepEqual(resolveExecutable(file,'win32'),{bin:file,prefix:[]});
});
test('native usage is current context rather than cumulative input',()=>{
 assert.deepEqual(normalizeUpdate({sessionUpdate:'usage_update',used:425,size:262144}),[{type:'context',tokens:425,context_window:262144}]);
});
