import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,existsSync,mkdirSync,symlinkSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
import {killProcessTree} from '../tools/agent/process-tree.mjs';
import {imagePermission} from '../tools/images/image-hook.mjs';
import {permittedImageTool} from '../tools/images/image-native-hook.mjs';

const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==','base64');
function fixture(t,harness='codex',mode='',extra={}){
  const base=mkdtempSync(join(tmpdir(),'gs-image-test-')),directory=join(base,'private'),workspace=join(base,'game');
  mkdirSync(directory);mkdirSync(workspace);writeFileSync(join(workspace,'keep.txt'),'unchanged');writeFileSync(join(workspace,'ref.png'),png);
  assembleHarnessRuntime(harness,directory);
  const config={harness,directory,workspace,prompt:'A circle',target_path:'assets/generated/circle.png',...extra};
  writeFileSync(join(directory,'job.json'),JSON.stringify(config));
  const variable={codex:'CODEX',agy:'AGY',cursor:'CURSOR','grok-build':'GROK_BUILD'}[harness];
  const child=spawn(process.execPath,[join(directory,'image-worker.mjs'),join(directory,'job.json')],{env:{...process.env,USERPROFILE:join(base,'native-home'),HOME:join(base,'native-home'),['GAMESMITH_'+variable+'_BIN']:resolve('tools/testing/fake-image-native.mjs'),GAMESMITH_IMAGE_FIXTURE:mode},windowsHide:true});
  let stderr='';child.stderr.on('data',b=>stderr+=b);const records=[],waiters=[];
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);for(const w of [...waiters])if(w.p(r)){waiters.splice(waiters.indexOf(w),1);clearTimeout(w.timer);w.resolve(r)}});
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid)});
  return {base,directory,workspace,child,records,until(p){const found=records.find(p);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const w={p,resolve,timer:setTimeout(()=>reject(Error('Image fixture timed out: '+stderr)),12000)};waiters.push(w)})},send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}
for(const harness of ['codex','agy','grok-build','cursor'])test(harness+': native artifact is staged and published only on host confirmation',async t=>{
  const f=fixture(t,harness);
  const {toolSpecs}=await import(pathToFileURL(join(f.directory,harness==='codex'?'tools.mjs':'workspace-tools.mjs')));
  assert(toolSpecs().some(tool=>tool.name==='gamesmith_generate_image'));
  await f.until(r=>r.type==='image_ready');
  assert.equal(existsSync(join(f.workspace,'assets/generated/circle.png')),false);
  writeFileSync(join(f.directory,'result.png'),png);f.send({id:'publish',type:'publish'});
  const r=await f.until(r=>r.id==='publish');assert.equal(r.success,true);assert.equal(r.path,'assets/generated/circle.png');
  assert.deepEqual(readFileSync(join(f.workspace,r.path)),png);assert.equal(readFileSync(join(f.workspace,'keep.txt'),'utf8'),'unchanged');
  if(harness==='codex'){
    const native=JSON.parse(readFileSync(join(f.directory,'native-workspace/thread-fixture.json')));
    assert.equal(native.ephemeral,true);assert.equal(native.sandbox,'read-only');assert.equal(native.approvalPolicy,'never');
    assert.equal(native.config.mcp_servers.unrelated.enabled,false);assert.equal(native.config.features.shell_tool,false);
  }
});
for(const harness of ['codex','agy','grok-build','cursor'])test(harness+': native failure never publishes or switches vendors',async t=>{
  const f=fixture(t,harness,'fail');const r=await f.until(r=>r.type==='image_error');assert.match(r.error,/Fixture image limit/);assert(!existsSync(join(f.workspace,'assets')));
});
test('publication rejects concurrent workspace edits',async t=>{
  const f=fixture(t);await f.until(r=>r.type==='image_ready');writeFileSync(join(f.workspace,'keep.txt'),'user edit');writeFileSync(join(f.directory,'result.png'),png);f.send({id:'publish',type:'publish'});
  const r=await f.until(r=>r.id==='publish');assert.equal(r.success,false);assert.match(r.error,/Workspace changed/);assert.equal(readFileSync(join(f.workspace,'keep.txt'),'utf8'),'user edit');
});
test('workspace boundaries reject traversal, absolute paths, links and non-images',async t=>{
  const directory=mkdtempSync(join(tmpdir(),'gs-image-boundary-'));assembleHarnessRuntime('codex',directory);
  const {prepareJob,imageBytes}=await import(pathToFileURL(join(directory,'image-job.mjs')));
  const workspace=join(directory,'workspace');mkdirSync(workspace);writeFileSync(join(workspace,'fake.png'),'not an image');
  for(const target_path of ['../outside.png',resolve(directory,'absolute.png'),'.git/config.png','.godot/asset.png'])await assert.rejects(()=>prepareJob({directory,workspace,target_path}));
  await assert.rejects(()=>imageBytes(join(workspace,'fake.png')),/Expected a PNG/);
  const outside=join(directory,'outside');mkdirSync(outside);symlinkSync(outside,join(workspace,'link'),'junction');
  await assert.rejects(()=>prepareJob({directory,workspace,target_path:'link/escape.png'}),/escapes/);
});
test('native image hooks reject shell, arbitrary writes and foreign delegation',()=>{
  for(const name of ['run_command','write_to_file','call_mcp_tool'])assert.equal(imagePermission({toolCall:{name,args:{}}}).decision,'deny');
  assert.equal(imagePermission({toolCall:{name:'generate_image'}}).decision,'auto_approve');
  assert.equal(imagePermission({toolCall:{name:'invoke_subagent',args:{Subagents:[{TypeName:'coding'}]}}}).decision,'deny');
  assert.equal(permittedImageTool({tool_name:'write',tool_input:{path:'main.gd'}},'grok-build','/job'),false);
  assert.equal(permittedImageTool({tool_name:'image_gen'},'grok-build','/job'),true);
  assert.equal(permittedImageTool({tool_name:'Write',tool_input:{file_path:'../escape.png'}},'cursor','/job'),false);
});
for(const harness of ['codex','agy','grok-build','cursor'])test(harness+': references are validated and staged outside the game',async t=>{
  const f=fixture(t,harness,'',{reference_paths:['ref.png']});await f.until(r=>r.type==='image_ready');assert.deepEqual(readFileSync(join(f.directory,'references/0.png')),png);
});

test('unexpected native file modifications reject the result',async t=>{
  const f=fixture(t,'codex','unexpected-edit');const result=await f.until(r=>r.type==='image_error');
  assert.match(result.error,/changed an unexpected file: unrelated.gd/);assert(!existsSync(join(f.workspace,'assets')));
});

test('image-edit hooks accept staged references and reject outside files',()=>{
  const base=mkdtempSync(join(tmpdir(),'gs-image-hook-')),cwd=join(base,'native-workspace');mkdirSync(cwd);mkdirSync(join(base,'references'));writeFileSync(join(base,'references/0.png'),png);
  const ref=join(base,'references/0.png');
  assert.equal(permittedImageTool({tool_name:'image_edit',tool_input:{image:[ref]}},'grok-build',cwd),true);
  assert.equal(permittedImageTool({tool_name:'image_edit',tool_input:{image:[join(base,'secret.png')]}},'grok-build',cwd),false);
  assert.equal(permittedImageTool({tool_name:'GenerateImage',tool_input:{reference_image_paths:[ref],filename:'output.png'}},'cursor',cwd),true);
  assert.equal(permittedImageTool({tool_name:'GenerateImage',tool_input:{filename:'../outside.png'}},'cursor',cwd),false);
});
test('capability detection rejects unavailable native capability without generating',async t=>{
  const f=fixture(t,'codex','no-capability',{probe:true});const r=await f.until(r=>r.type==='image_capability');assert.equal(r.available,false);assert.match(r.reason,/does not advertise/);assert(!existsSync(join(f.directory,'result.raw')));
});

test('AGY discovers the single image belonging to its dedicated image-generator subagent',async t=>{
  const f=fixture(t,'agy','agy-subagent');await f.until(r=>r.type==='image_ready');
  assert.deepEqual(readFileSync(join(f.directory,'result.raw')),png);
});
test('AGY rejects ambiguous native artifacts instead of guessing',async t=>{
  const f=fixture(t,'agy','agy-ambiguous');const r=await f.until(r=>r.type==='image_error');assert.match(r.error,/multiple image artifacts/);
});
for(const mode of ['agy-foreign','agy-reference'])test('AGY rejects an artifact from '+mode,async t=>{
  const f=fixture(t,'agy',mode,{reference_paths:['ref.png']});const r=await f.until(r=>r.type==='image_error');assert.match(r.error,/escaped its allowed output locations/);assert(!existsSync(join(f.workspace,'assets')));
});
for(const harness of ['codex','agy','grok-build','cursor'])test(harness+': cancellation kills the native image child and publishes nothing',async t=>{
  const f=fixture(t,harness,'wait'),marker=join(f.directory,'native-wait.txt');
  for(let i=0;i<600 && !existsSync(marker);i++)await new Promise(resolve=>setTimeout(resolve,10));
  assert(existsSync(marker),'native image operation started');const pid=Number(readFileSync(marker,'utf8'));
  const alive=()=>{try{process.kill(pid,0);return process.platform!=='linux' || !readFileSync('/proc/'+pid+'/stat','utf8').includes(') Z ');}catch{return false;}};
  assert(alive());killProcessTree(f.child.pid);
  for(let i=0;i<300 && alive();i++)await new Promise(resolve=>setTimeout(resolve,10));
  assert.equal(alive(),false,'native image process exits');assert(!existsSync(join(f.workspace,'assets')));
});
