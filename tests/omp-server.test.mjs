import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync,readdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {killProcessTree} from '../tools/agent/process-tree.mjs';

function fixture(t,extra={},saved,directory=mkdtempSync(join(tmpdir(),'gs-omp-runtime-'))){
  mkdirSync(join(directory,'bridge'),{recursive:true});
  // Exercise the controller's actual assembled bundle, including shared modules.
  const controller=readFileSync('src/agent/omp_agent_controller.gd','utf8').split('func _native_modules()')[1].split('func _native_prompt()')[0];
  const inherited=readFileSync('src/agent/cline_agent_controller.gd','utf8').split('for pair in _native_modules() + ')[1].split(':')[0];
  const pairs=[...controller.matchAll(/\["([^"]+)", "([^"]+)"\]/g),...inherited.matchAll(/\["([^"]+)", "([^"]+)"\]/g)];
  assert.equal(pairs.length,7);
  for(const [,target,source] of pairs)copyFileSync(join('tools',source),join(directory,target));
  const config={workspace:directory,bridge_dir:join(directory,'bridge'),session_file:join(directory,'session.json'),prompt_path:join(directory,'prompt.md')};
  if(saved){config.session=saved;writeFileSync(config.session_file,JSON.stringify({session:saved}));}
  const trace=join(directory,'trace.jsonl');writeFileSync(trace,'');
  writeFileSync(config.prompt_path,'Use only GameSmith tools.');writeFileSync(join(directory,'runtime.json'),JSON.stringify(config));
  const child=spawn(process.execPath,[join(directory,'worker.mjs'),join(directory,'runtime.json')],{env:{...process.env,GAMESMITH_OMP_BIN:resolve('tools/testing/fake-omp.mjs'),GAMESMITH_OMP_TRACE:trace,...extra},windowsHide:true});
  const records=[],waiters=[];let stderr='';child.stderr.on('data',d=>stderr+=d);
  createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);for(const w of [...waiters])if(w.predicate(r)){waiters.splice(waiters.indexOf(w),1);w.resolve(r);}});
  function until(predicate,timeout=10000){const found=records.find(predicate);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Fixture timed out: '+stderr)),timeout);waiters.push({predicate,resolve:r=>{clearTimeout(timer);resolve(r);}});});}
  t.after(()=>{if(child.exitCode===null)killProcessTree(child.pid);});
  return {directory,child,records,until,trace:()=>readFileSync(trace,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse),send:r=>child.stdin.write(JSON.stringify(r)+'\n')};
}

test('assembled runtime reconciles partial streaming, uses native context and reuses backend',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,true);assert.equal(result.text,'Fixture complete');
  assert.equal(f.records.filter(r=>r.type==='delta' && r.kind==='assistant').map(r=>r.text).join(''),result.text);
  assert.equal((await f.until(r=>r.type==='context')).tokens,4321);
  const backend=JSON.parse(readFileSync(join(f.directory,'backend.json')));assert.equal(backend.tools.length,18);assert.equal(backend.model,'fixture-free');
  f.send({type:'prompt',id:'two',message:'/compact'});assert.equal((await f.until(r=>r.id==='two')).success,true);
  while(f.records.filter(r=>r.type==='complete').length<2)await new Promise(r=>setTimeout(r,10));
  assert.equal(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,backend.pid);
  assert.deepEqual(f.trace().filter(r=>r.type==='prompt').map(r=>r.message),['/gamesmith-ready','Player request:\nhello','Player request:\n/compact']);
  const overlay=JSON.parse(readFileSync(join(f.directory,'native','config.yml')));assert.equal('model' in overlay,false);assert.equal('compaction' in overlay,false);
});

test('OMP host results carry Blender previews as native image blocks',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'image',message:'blender-image'});
  const bridge=join(f.directory,'bridge');let file;
  while(!file){file=readdirSync(bridge).find(n=>/^request-.*\.json$/.test(n));if(!file)await new Promise(r=>setTimeout(r,10));}
  const request=JSON.parse(readFileSync(join(bridge,file),'utf8'));assert.equal(request.command,'blender');
  writeFileSync(join(bridge,file.replace('request-','response-')),JSON.stringify({ok:true,image_base64:'aW1hZ2U=',mime_type:'image/png'}));
  assert.equal((await f.until(r=>r.type==='complete')).ok,true);
  const content=f.trace().find(r=>r.type==='host_tool_result').result.content;
  assert.deepEqual(content[1],{type:'image',mimeType:'image/png',data:'aW1hZ2U='});
  assert(!content[0].text.includes('aW1hZ2U='));
});

test('unknown tools and workspace escapes fail before side effects',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'policy'});assert.equal((await f.until(r=>r.type==='complete')).ok,true);
  const results=f.trace().filter(r=>r.type==='host_tool_result');assert.equal(results.length,2);assert(results.every(r=>r.isError));
  assert.equal(existsSync(join(f.directory,'..','escaped.txt')),false);
});

test('final reconciliation preserves earlier assistant rounds',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'multiple-rounds'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,true);assert.equal(result.text,'Working. Fixture complete');
  assert.equal(f.records.filter(r=>r.type==='delta' && r.kind==='assistant').map(r=>r.text).join(''),result.text);
});

test('prompt yield waits for native session settlement before handing control back',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'delayed-settlement'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,true);assert.equal(result.text,'Fixture complete settled');
});

test('back-to-back turns consume even a late settled=true frame before starting the next turn',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'late-settlement'});
  await f.until(r=>r.type==='complete');
  const before=f.records.length;
  f.send({type:'prompt',id:'two',message:'delayed-settlement'});
  const second=await f.until(r=>f.records.indexOf(r)>=before && r.type==='complete');
  assert.equal(second.text,'Fixture complete settled');
  const trace=f.trace(),first=trace.find(r=>r.type==='prompt' && r.message.endsWith('late-settlement'));
  const settlement=trace.findIndex(r=>r.type==='fixture_settled' && r.promptId===first.id);
  const next=trace.findIndex(r=>r.type==='prompt' && r.message.endsWith('delayed-settlement'));
  assert(settlement>=0 && settlement<next,'first settlement must precede the next native prompt');
});

test('idle native backend death terminates the worker and preserves the resumable session',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});
  assert((await f.until(r=>r.type==='complete')).ok);
  const saved=JSON.parse(readFileSync(join(f.directory,'session.json'))).session;
  const backend=JSON.parse(readFileSync(join(f.directory,'backend.json')));
  const closed=new Promise(resolve=>f.child.once('close',resolve));
  killProcessTree(backend.pid);
  let timer;
  try { await Promise.race([closed,new Promise((_,reject)=>timer=setTimeout(()=>reject(new Error('Idle worker survived native backend death')),1500))]); }
  finally { clearTimeout(timer); }
  assert.notEqual(f.child.exitCode,0);
  const resumed=fixture(t,{},saved,f.directory);resumed.send({type:'prompt',id:'two',message:'hello'});
  assert((await resumed.until(r=>r.type==='complete')).ok);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,saved);
  assert.notEqual(JSON.parse(readFileSync(join(f.directory,'backend.json'))).pid,backend.pid);
});

test('local-only prompt admission does not wait for an agent settlement frame',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'local-only'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,true);assert.equal(result.text,'');
});

test('bounded recent IDs preserve active-turn and recent cross-turn replay denial',{timeout:30000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'replay-window'});
  assert.equal((await f.until(r=>r.type==='complete',25000)).text,'Active replay denied after recent cache eviction');
  const before=f.records.length;
  f.send({type:'prompt',id:'two',message:'recent-replay'});
  assert.equal((await f.until(r=>f.records.indexOf(r)>=before && r.type==='complete')).text,'Recent cross-turn replay denied');
  assert.equal(f.trace().filter(r=>r.type==='host_tool_result' && r.isError).length,2);
});

test('fresh readiness nonce is required before player inference',{timeout:15000},async t=>{
  const f=fixture(t,{GAMESMITH_OMP_BAD_POLICY:'1'});f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);assert.match(result.error,/readiness/);
  assert.equal(f.trace().some(r=>r.type==='prompt' && r.message.startsWith('Player request:')),false);
  assert.equal(existsSync(join(f.directory,'session.json')),false);
});

test('missing policy readiness has a bounded startup deadline, not a model timeout',{timeout:40000},async t=>{
  const f=fixture(t,{GAMESMITH_OMP_NO_POLICY:'1'});const start=Date.now();f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response',35000);assert.equal(result.success,false);assert.equal(result.initialization_failed,true);assert.match(result.error,/30 seconds/);
  assert(Date.now()-start<35000);assert.equal(f.trace().some(r=>r.type==='prompt' && r.message.startsWith('Player request:')),false);
});

test('missing saved history remains recoverable without changing its reference',{timeout:15000},async t=>{
  const f=fixture(t,{},'missing.jsonl');f.send({type:'prompt',id:'one',message:'hello'});
  const result=await f.until(r=>r.type==='response');assert.equal(result.success,false);assert.equal(result.initialization_failed,true);assert.match(result.error,/Start a new OMP session/);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,'missing.jsonl');assert.equal(f.trace().length,0);
});

test('explicit saved file survives worker recreation and native Stop',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'hello'});assert((await f.until(r=>r.type==='complete')).ok);
  const saved=JSON.parse(readFileSync(join(f.directory,'session.json'))).session;
  const exited=new Promise(resolve=>f.child.once('close',resolve));f.child.stdin.end();await exited;
  const resumed=fixture(t,{},saved,f.directory);resumed.send({type:'prompt',id:'two',message:'wait'});assert((await resumed.until(r=>r.id==='two')).success);
  resumed.send({type:'cancel',id:'stop'});assert((await resumed.until(r=>r.id==='stop')).success);
  assert.equal(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,saved);
});

test('backend exit requests host retirement rather than poisoning subsequent requests',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'exit-backend'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.equal(result.runtime_failed,true);assert.notEqual(result.initialization_failed,true);
});

test('provider failure settles without forgetting established native history',{timeout:15000},async t=>{
  const f=fixture(t);f.send({type:'prompt',id:'one',message:'provider-error'});
  const result=await f.until(r=>r.type==='complete');assert.equal(result.ok,false);assert.match(result.error,/Fixture provider error/);
  assert.match(JSON.parse(readFileSync(join(f.directory,'session.json'))).session,/\.jsonl$/);
});
