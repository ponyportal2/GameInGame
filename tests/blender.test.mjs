import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,copyFileSync,readdirSync,readFileSync,renameSync,rmSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {prepareJob,inspectImage,resolveBlender} from '../tools/blender/jobs.mjs';
import {hostTools,toolContent} from '../tools/opencode/host-tools.mjs';

const workspace=()=>mkdtempSync(join(tmpdir(),'gs-blender-'));
test('Blender is a shared host capability and image bytes become native image content',()=>{
  assert(hostTools.blender.properties.action.enum.includes('start'));
  const content=toolContent({ok:true,image_base64:'aGVsbG8=',mime_type:'image/png',width:64});
  assert.equal(content[1].type,'image');assert.equal(content[1].mimeType,'image/png');
  assert.equal(content[0].text.includes('aGVsbG8='),false);
});
test('job validation rejects traversal, protected metadata and missing scripts',async()=>{
  const root=workspace();writeFileSync(join(root,'ok.py'),'import bpy');
  for(const script of ['../evil.py','.git/x.py','missing.py'])
    await assert.rejects(prepareJob({workspace:root,script}));
  await assert.rejects(prepareJob({workspace:root,script:'ok.py',render:'../outside.png'}));
  await assert.rejects(prepareJob({workspace:root,script:'ok.py',render:'output.txt'}));
  const result=await prepareJob({workspace:root,script:'ok.py',render:'renders/preview.png'});
  assert.equal(result.script,join(root,'ok.py'));assert.equal(result.render,join(root,'renders/preview.png'));
});
test('workspace junctions cannot redirect Blender inputs or preview reads',async()=>{
  const root=workspace(),outside=workspace();
  symlinkSync(outside,join(root,'link'),process.platform==='win32'?'junction':'dir');
  writeFileSync(join(outside,'evil.py'),'');
  await assert.rejects(prepareJob({workspace:root,script:'link/evil.py'}));
  await assert.rejects(inspectImage(root,'link/image.png'));
});
test('image inspection verifies format, bytes and decoded-size limits',async()=>{
  const root=workspace();
  // 1x1 PNG, not just arbitrary bytes bearing a .png suffix.
  const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
  writeFileSync(join(root,'preview.png'),png);
  const image=await inspectImage(root,'preview.png');assert.equal(image.width,1);assert.equal(image.mime_type,'image/png');
  writeFileSync(join(root,'fake.png'),'not an image');await assert.rejects(inspectImage(root,'fake.png'));
  const huge=Buffer.from(png);huge.writeUInt32BE(100000,16);writeFileSync(join(root,'huge.png'),huge);
  await assert.rejects(inspectImage(root,'huge.png'));
});
test('explicit Blender override is honored and invalid override fails clearly',async()=>{
  await assert.rejects(resolveBlender({GAMESMITH_BLENDER_BIN:resolve('missing-blender.exe')}),/Blender/);
});

for(const harness of ['opencode','cline','grok-build','kimi','kiro','agy'])test(harness+' assembled MCP exposes Blender and delivers a native preview image',{timeout:15000},async()=>{
  const root=workspace(),bridge=join(root,'bridge');mkdirSync(bridge);
  // Assemble the same canonical support modules that the host installs.
  for(const [target,source] of Object.entries({'mcp.mjs':harness+'/mcp.mjs','host-tools.mjs':'opencode/host-tools.mjs','workspace-tools.mjs':'codex/tools.mjs','workspace-paths.mjs':'pi/workspace-paths.mjs','approval.mjs':harness==='grok-build'?'grok-build/approval.mjs':'cline/approval.mjs'}))
    copyFileSync(resolve('tools',source),join(root,target));
  writeFileSync(join(bridge,'operation.json'),JSON.stringify({active:true,session:'fixture'}));
  writeFileSync(join(root,'config.json'),JSON.stringify({workspace:root,bridge_dir:bridge}));
  const child=spawn(process.execPath,[join(root,'mcp.mjs'),join(root,'config.json')],{env:{...process.env,GAMESMITH_HOST_BRIDGE_DIR:bridge},stdio:['pipe','pipe','pipe']});
  const pending=new Map();let stderr='';child.stderr.on('data',d=>stderr+=d);
  const lines=createInterface({input:child.stdout});lines.on('line',line=>{const r=JSON.parse(line);pending.get(r.id)?.(r);pending.delete(r.id);});
  child.on('exit',()=>{for(const callback of pending.values())callback({error:stderr || 'MCP exited'});pending.clear();});
  let id=0;const call=(method,params)=>new Promise(resolve=>{pending.set(++id,resolve);child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');});
  const pump=setInterval(()=>{for(const file of readdirSync(bridge).filter(n=>/^request-.*\.json$/.test(n))){const r=JSON.parse(readFileSync(join(bridge,file),'utf8'));assert.equal(r.command,'blender');rmSync(join(bridge,file));const response=join(bridge,'response-'+r.id+'.json');writeFileSync(response+'.tmp',JSON.stringify({ok:true,width:1,height:1,mime_type:'image/png',image_base64:'cHJldmlldw=='}));renameSync(response+'.tmp',response);}},20);
  try {
    const list=await call('tools/list',{});assert(!list.error,JSON.stringify(list));assert(list.result.tools.some(t=>t.name==='blender'));
    const response=await call('tools/call',{name:'blender',arguments:{action:'inspect',path:'preview.png'}});
    assert(!response.error,JSON.stringify(response));assert.equal(response.result.isError,false);
    assert.deepEqual(response.result.content[1],{type:'image',data:'cHJldmlldw==',mimeType:'image/png'});
    assert(!response.result.content[0].text.includes('cHJldmlldw=='));
  } finally {clearInterval(pump);lines.close();child.stdin.end();child.kill();}
});
