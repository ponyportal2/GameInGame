import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,copyFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {permissionResult,normalizeUpdate} from '../tools/copilot/protocol.mjs';

test('every ACP permission is denied regardless of display title or call ID',()=>{
 for(const toolCall of [{title:'powershell'},{title:'gamesmith-write',toolCallId:'known'},{name:'gamesmith-write',toolCallId:'known',rawInput:{}}]){
  assert.deepEqual(permissionResult({toolCall,options:[{kind:'allow_once',optionId:'yes'},{kind:'reject_once',optionId:'no'}]}),{outcome:{outcome:'selected',optionId:'no'}});
 }
 assert.deepEqual(permissionResult({options:[{kind:'allow_always',optionId:'yes'}]}),{outcome:{outcome:'cancelled'}});
});
test('current native usage is distinct from per-turn totals',()=>{
 assert.deepEqual(normalizeUpdate({sessionUpdate:'usage_update',used:4321,size:272000}),[{type:'context',tokens:4321}]);
 for(const used of [-1,Infinity,NaN,undefined])assert.deepEqual(normalizeUpdate({sessionUpdate:'usage_update',used}),[]);
 assert.deepEqual(normalizeUpdate({usage:{totalTokens:999999}}),[]);
});
test('native startup information remains visible and separated from assistant text',()=>{
 const chunk=text=>({sessionUpdate:'agent_message_chunk',content:{type:'text',text}});
 assert.equal(normalizeUpdate(chunk('Info: Disabled tools: powershell, view'))[0].text,'Info: Disabled tools: powershell, view\n\n');
 assert.equal(normalizeUpdate(chunk('37'))[0].text,'37');
 assert.equal(normalizeUpdate(chunk('Info: this is ordinary assistant text'))[0].text,'Info: this is ordinary assistant text');
});
test('Windows Copilot npm shims resolve without PowerShell or generic agent',async()=>{
 const directory=mkdtempSync(join(tmpdir(),'gs-copilot-resolve-'));
 // Load the same flat transport bundle shipped by the controller.
 copyFileSync('tools/copilot/server.mjs',join(directory,'server.mjs'));
 writeFileSync(join(directory,'workspace-tools.mjs'),'export const toolSpecs=()=>[];');
 copyFileSync('tools/agent/process-tree.mjs',join(directory,'process-tree.mjs'));
 const {resolveExecutable}=await import(pathToFileURL(join(directory,'server.mjs')));
 const native=join(directory,'copilot.exe');writeFileSync(native,'fixture');
 assert.deepEqual(resolveExecutable(native,'win32'),{bin:native,prefix:[]});
 const entry=join(directory,'node_modules','@github','copilot','npm-loader.js');mkdirSync(join(directory,'node_modules','@github','copilot'),{recursive:true});writeFileSync(entry,'// fixture');
 for(const extension of ['cmd','ps1']){
  const shim=join(directory,'copilot.'+extension);writeFileSync(shim,'fixture');
  assert.deepEqual(resolveExecutable(shim,'win32'),{bin:process.execPath,prefix:[entry]});
 }
 const js=resolve('tools/testing/fake-copilot.mjs');assert.deepEqual(resolveExecutable(js,'win32'),{bin:process.execPath,prefix:[js]});
 assert.deepEqual(resolveExecutable('copilot','linux'),{bin:'copilot',prefix:[]});
});
