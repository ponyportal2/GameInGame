import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,symlinkSync,copyFileSync,readdirSync,readFileSync,renameSync,rmSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {prepareJob,inspectImage,resolveBlender,reviewScript,approvedJob,blenderEnvironment} from '../tools/blender/jobs.mjs';
import {hostTools,toolContent} from '../tools/opencode/host-tools.mjs';
import {processIdentity,cleanupJob} from '../tools/blender/ownership.mjs';

const workspace=()=>mkdtempSync(join(tmpdir(),'gs-blender-'));
test('script approval is bound to reviewed bytes and a private snapshot',async()=>{
  const root=workspace(),directory=workspace();
  const config={workspace:root,directory,script:'build.py'};
  writeFileSync(join(root,'build.py'),'print("approved")\n');
  await assert.rejects(approvedJob(config),/approval/i);
  const review=await reviewScript(config);
  assert.equal(review.source,'print("approved")\n');assert.match(review.sha256,/^[a-f0-9]{64}$/);
  const approved={...config,script_sha256:review.sha256};
  const job=await approvedJob(approved);
  assert.equal(job.script,join(directory,'approved.py'));
  writeFileSync(join(root,'build.py'),'print("changed")\n');
  await assert.rejects(approvedJob(approved),/changed/i);
  writeFileSync(join(root,'build.py'),review.source);
  writeFileSync(join(directory,'approved.py'),'print("tampered snapshot")\n');
  await assert.rejects(approvedJob(approved),/snapshot/i);
});
test('script review enforces paths, displayable UTF-8 and a bounded size',async()=>{
  const root=workspace(),directory=workspace();
  for(const script of ['../bad.py','.git/private.py','missing.py'])
    await assert.rejects(reviewScript({workspace:root,directory,script}));
  writeFileSync(join(root,'bad.py'),Buffer.from([255,254]));
  await assert.rejects(reviewScript({workspace:root,directory,script:'bad.py'}));
  writeFileSync(join(root,'large.py'),'#'.repeat(256*1024+1));
  await assert.rejects(reviewScript({workspace:root,directory,script:'large.py'}),/256/);
});
test('Blender receives a minimal OS environment, without credentials or Python injection',()=>{
  const env=blenderEnvironment({PATH:'bin',SystemRoot:'windows',TEMP:'tmp',HOME:'home',OPENAI_API_KEY:'secret',AWS_SECRET_ACCESS_KEY:'secret',GITHUB_TOKEN:'secret',PYTHONPATH:'injection',NODE_OPTIONS:'injection',ARBITRARY_SECRET:'secret'},'private','workspace');
  assert.equal(env.SystemRoot,'windows');assert.equal(env.HOME,'home');
  assert.equal(env.BLENDER_USER_CONFIG,'private');assert.equal(env.GAMESMITH_WORKSPACE,'workspace');
  for(const key of ['PATH','OPENAI_API_KEY','AWS_SECRET_ACCESS_KEY','GITHUB_TOKEN','PYTHONPATH','NODE_OPTIONS','ARBITRARY_SECRET'])assert.equal(env[key],undefined);
});
test('orphan recovery verifies process birth and private job marker before terminating',{timeout:45000},async()=>{
  const directory=workspace(),marker=join(directory,'prepared.json');
  const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)',marker],{stdio:'ignore',windowsHide:true});
  const exit=new Promise(resolve=>child.once('exit',resolve));
  try {
    const identity=await processIdentity(child.pid);
    assert(identity?.command.includes(marker));
    const status={run_id:'owned',pid:child.pid,identity:{...identity,birth:'wrong-birth'}};
    writeFileSync(join(directory,'status.json'),JSON.stringify(status));
    assert.equal((await cleanupJob({directory,run_id:'owned'})).killed,false);
    assert.equal(child.exitCode,null);
    status.identity=identity;status.run_id='wrong-job';
    writeFileSync(join(directory,'status.json'),JSON.stringify(status));
    await assert.rejects(cleanupJob({directory,run_id:'owned'}),/ownership/);
    status.run_id='owned';status.identity={...identity,command:'unrelated process'};
    writeFileSync(join(directory,'status.json'),JSON.stringify(status));
    await assert.rejects(cleanupJob({directory,run_id:'owned'}),/ownership/);
    assert.equal(child.exitCode,null);
    status.identity=identity;writeFileSync(join(directory,'status.json'),JSON.stringify(status));
    assert.equal((await cleanupJob({directory,run_id:'owned'})).killed,true);
    await exit;
    assert.equal((await cleanupJob({directory,run_id:'owned'})).killed,false);
  }finally {child.kill();await exit;}
});
test('Blender is a shared host capability and image bytes become native image content',()=>{
  assert(hostTools.blender.properties.action.enum.includes('start'));
  assert.equal(hostTools.blender.properties.details.type,'boolean');
  assert.equal(hostTools.blender.properties.offset.type,'integer');
  assert.equal(hostTools.test_game_action.properties.depth.maximum,4);
  const pi = readFileSync(new URL('../tools/pi/gamesmith-extension.ts',import.meta.url),'utf8');
  assert.match(pi.split('name: "blender"')[1].split('name:')[0],/details: Type.Optional/);
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
    if(['cline','grok-build'].includes(harness)){
      const denied=await call('tools/call',{name:'blender',arguments:{action:'start',script:'build.py'}});
      assert.equal(denied.result.isError,true);assert.match(denied.result.content[0].text,/no active ACP approval/);
    }
  } finally {clearInterval(pump);lines.close();child.stdin.end();child.kill();}
});

for(const harness of ['cline','grok-build'])test(harness+' waits for ACP Blender approval and consumes an exact single-use grant',async()=>{
  const {authorizeBlender,consumeBlenderGrant}=await import('../tools/'+harness+'/approval.mjs');
  const bridge_dir=workspace(),config={bridge_dir},args={action:'start',script:'build.py'};
  const abort=new AbortController();
  const pending=authorizeBlender(config,args,abort.signal);
  const waitRequest=async()=>{
    for(let i=0;i<200;i++){
      const name=readdirSync(bridge_dir).find(n=>/^request-.*\.json$/.test(n));
      if(name)return JSON.parse(readFileSync(join(bridge_dir,name),'utf8'));
      await new Promise(r=>setTimeout(r,10));
    }
    throw new Error('No authorization request');
  };
  const request=await waitRequest();
  assert.equal(request.command,'authorize_blender');assert.deepEqual(request.args.blender_args,args);
  await assert.rejects(consumeBlenderGrant(config,args),/no active/);
  writeFileSync(join(bridge_dir,'response-'+request.id+'.json'),JSON.stringify({ok:true}));await pending;
  await assert.rejects(consumeBlenderGrant(config,{...args,script:'other.py'}),/match/);
  await assert.rejects(consumeBlenderGrant(config,args),/no active/);
  const accepted=authorizeBlender(config,args,abort.signal),second=await waitRequest();
  writeFileSync(join(bridge_dir,'response-'+second.id+'.json'),JSON.stringify({ok:true}));await accepted;
  assert.equal(await consumeBlenderGrant(config,args),second.args.token);
  await assert.rejects(consumeBlenderGrant(config,args),/no active/);
  const cancelled=authorizeBlender(config,args,abort.signal);await waitRequest();abort.abort();
  await assert.rejects(cancelled,/abort/i);
  assert.equal(readdirSync(bridge_dir).length,0);
});
