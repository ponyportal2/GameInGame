import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
const runtime=mkdtempSync(join(tmpdir(),'gs-codebuddy-contract-'));
assembleHarnessRuntime('codebuddy',runtime);
const {PermissionCalls,normalizeUpdate}=await import(pathToFileURL(join(runtime,'protocol.mjs')));
const {resolveExecutable,launchArgs}=await import(pathToFileURL(join(runtime,'server.mjs')));
const {toolSpecs}=await import(pathToFileURL(join(runtime,'workspace-tools.mjs')));

test('CodeBuddy is selectable with native settings, independent session reset and assembled modules',()=>{
 const h=JSON.parse(readFileSync('tools/agent/harnesses.json')).harnesses.find(h=>h.id==='codebuddy');
 assert(h);assert.equal(h.native_settings,true);assert.equal(h.reset,true);
 assert.equal(h.launcher.command,'codebuddy');assert.equal(h.launcher.env,'GAMESMITH_CODEBUDDY_BIN');
 assert(h.modules.some(([dest,path])=>dest==='server.mjs' && path==='codebuddy/server.mjs'));
});

test('Windows npm resolution runs CodeBuddy directly without a shell or a second agent',()=>{
 const directory=mkdtempSync(join(tmpdir(),'gs-codebuddy-resolve-'));
 const shim=join(directory,'codebuddy.cmd'),entry=join(directory,'node_modules/@tencent-ai/codebuddy-code/bin/codebuddy');
 mkdirSync(join(directory,'node_modules/@tencent-ai/codebuddy-code/bin'),{recursive:true});writeFileSync(shim,'fixture');writeFileSync(entry,'fixture');
 assert.deepEqual(resolveExecutable(shim,'win32'),{bin:process.execPath,prefix:[entry]});
 const exe=join(directory,'codebuddy.exe');writeFileSync(exe,'fixture');assert.deepEqual(resolveExecutable(exe,'win32'),{bin:exe,prefix:[]});
 assert.throws(()=>resolveExecutable(join(directory,'missing.cmd'),'win32'),/CodeBuddy/);
});

test('ACP launch disables builtins and external MCP without overriding native model or reasoning',()=>{
 const prompt=join(runtime,'instructions.md');writeFileSync(prompt,'GameSmith instructions');
 const args=launchArgs({prompt_path:prompt});
 assert(args.includes('--acp'));
 assert.deepEqual(args[args.indexOf('--tools')+1].split(','),toolSpecs().map(t=>'NoDefer(mcp__gamesmith__'+t.name.slice(10)+')'));
 assert.equal(args[args.indexOf('--tool-mode')+1],'cli');
 assert(args.includes('--strict-mcp-config'));assert.equal(args[args.indexOf('--mcp-config')+1],'{"mcpServers":{}}');
 assert.equal(args[args.indexOf('--permission-mode')+1],'default');
 for(const flag of ['--model','--effort','--dangerously-skip-permissions','--continue','--resume-create-missing'])assert(!args.includes(flag));
});

test('permissions require exact CodeBuddy tool metadata, current call identity and one use',()=>{
 const seen=new Set(),calls=new PermissionCalls(seen);
 const announcement={sessionUpdate:'tool_call',toolCallId:'one',kind:'other',status:'pending',_meta:{'codebuddy.ai/toolName':'mcp__gamesmith__write'}};
 calls.update(announcement);
 assert.equal(calls.take({toolCallId:'unknown',_meta:announcement._meta}),false);
 assert.equal(calls.take({toolCallId:'one',_meta:announcement._meta}),true);
 assert.equal(calls.take({toolCallId:'one',_meta:announcement._meta}),false);
 const next=new PermissionCalls(seen);next.update(announcement);assert.equal(next.take({toolCallId:'one',_meta:announcement._meta}),false);
 for(const name of ['Bash','mcp__outside__write','mcp__gamesmith__not_a_tool','mcp__gamesmith__write_extra']){
  const c=new PermissionCalls();c.update({...announcement,_meta:{'codebuddy.ai/toolName':name}});
  assert.equal(c.take({toolCallId:'one',title:'mcp__gamesmith__write',_meta:{'codebuddy.ai/toolName':name}}),false);
 }
 const changed=new PermissionCalls();changed.update(announcement);assert.equal(changed.take({toolCallId:'one',_meta:{'codebuddy.ai/toolName':'Bash'}}),false);
});

test('streamed text and actual current context are normalized without cumulative token guessing',()=>{
 assert.deepEqual(normalizeUpdate({sessionUpdate:'agent_message_chunk',content:{type:'text',text:'Hello'}}),[{type:'delta',kind:'assistant',text:'Hello'}]);
 assert.deepEqual(normalizeUpdate({sessionUpdate:'usage_update',used:450,size:128000}),[{type:'context',tokens:450,context_window:128000}]);
 assert.deepEqual(normalizeUpdate({sessionUpdate:'usage_update',used:-1}),[]);
});
