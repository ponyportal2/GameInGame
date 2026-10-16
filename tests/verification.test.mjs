import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {parseArgs,runVerification} from '../tools/testing/verify.mjs';
import {fingerprint,reusedTests} from '../tools/testing/verification-evidence.mjs';
import {selectTests,inventory,resolveTest} from '../tools/testing/verification-plan.mjs';
import {generatedLauncher,exportFilter} from '../tools/testing/generate-harness-inventory.mjs';
import {atomicSaveSession,failureRecord} from '../tools/agent/session-state.mjs';
const root=resolve('.');
function repository(t){
 const dir=mkdtempSync(join(tmpdir(),'gs-verify-spec-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 mkdirSync(join(dir,'tools/agent'),{recursive:true});mkdirSync(join(dir,'tests'));
 writeFileSync(join(dir,'tools/agent/harnesses.json'),'{"harnesses":[]}');
 writeFileSync(join(dir,'tests/good.test.mjs'),"import {test} from 'node:test';test('expected error text',()=>console.log('ERROR: deliberate fixture diagnostic'));\n");
 writeFileSync(join(dir,'tests/bad.test.mjs'),"import {test} from 'node:test';test('failure',()=>{throw new Error('fixture broken')});\n");
 for(const args of [['init','-q'],['add','.'],['-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture']])assert.equal(spawnSync('git',args,{cwd:dir,windowsHide:true}).status,0);
 return dir;
}
test('output views preserve complete evidence; exit state wins over ERROR text',async t=>{
 const dir=repository(t);let prior;
 for(const output of ['summary','errors','full']){
  const result=await runVerification(parseArgs(['--suite','node','--output',output]),dir);
  assert.equal(result.status,'failed');assert.deepEqual(result.tests.map(t=>[t.id,t.status]).sort(([a],[b])=>a.localeCompare(b)),[['node:bad','failed'],['node:good','passed']]);
  assert.equal(existsSync(result.tests.find(t=>t.id==='node:bad').diagnostics[0].file),true);
  assert.match(readFileSync(result.tests.find(t=>t.id==='node:good').log,'utf8'),/ERROR: deliberate/);
  assert.equal(JSON.parse(readFileSync(result.results_path)).status,'failed');
  prior=result;
 }
 writeFileSync(join(dir,'tests/bad.test.mjs'),"import {test} from 'node:test';test('fixed',()=>{});\n");
 const rerun=await runVerification(parseArgs(['--rerun-failed',prior.results_path]),dir);
 assert.deepEqual(rerun.selection,['node:bad']);assert.equal(rerun.status,'passed');
 const fresh=await runVerification(parseArgs(['--suite','node']),dir);
 const reused=await runVerification(parseArgs(['--suite','node','--reuse',fresh.results_path]),dir);
 assert(reused.tests.every(t=>t.status==='reused'&&t.evidence_from===fresh.results_path));
 writeFileSync(join(dir,'tests/good.test.mjs'),"import {test} from 'node:test';test('changed',()=>{});\n");
 const invalidated=await runVerification(parseArgs(['--suite','node','--reuse',fresh.results_path]),dir);
 assert(invalidated.tests.every(t=>t.status==='passed'));
});
test('fingerprints invalidate content, runtime, suite and environment changes',t=>{
 const dir=repository(t),tests=[{id:'one'}],base=fingerprint(dir,tests,{node:'one'},{CI:'one'});
 assert.notEqual(base.fingerprint,fingerprint(dir,tests,{node:'two'},{CI:'one'}).fingerprint);
 assert.notEqual(base.fingerprint,fingerprint(dir,[{id:'two'}],{node:'one'},{CI:'one'}).fingerprint);
 assert.notEqual(base.fingerprint,fingerprint(dir,tests,{node:'one'},{CI:'two'}).fingerprint);
 assert.deepEqual(reusedTests({status:'passed',fingerprint:base.fingerprint,tests:[{id:'one',status:'passed',log:'missing-file'}]},tests,base.fingerprint),[]);
});
test('inventory paths and launcher stay synchronized; affected mapping is conservative',()=>{
 const catalog=JSON.parse(readFileSync('tools/agent/harnesses.json'));
 assert.equal(new Set(inventory(root).map(h=>h.id)).size,14);
 for(const h of catalog.harnesses){
  assert(existsSync(h.controller));assert(new Set(h.modules.map(p=>p[0])).size===h.modules.length);
  for(const [target,source] of h.modules){assert(!target.includes('..')&&!target.includes('/'));assert(existsSync('tools/'+source));for(const match of readFileSync('tools/'+source,'utf8').matchAll(/(?:from\s*|import\s*\()\s*['"]\.\/([^'"]+)['"]/g))assert(h.modules.some(([name])=>name===match[1]),h.id+' runtime missing '+match[1]);}
  for(const file of [...h.node_suites,...h.host_runners])assert(existsSync(file),file);
 }
 assert.equal(readFileSync('export_presets.cfg','utf8').match(/^include_filter="(.*)"/m)[1],exportFilter(catalog));
 assert.equal(readFileSync('tools/windows-bootstrap/harness_inventory_generated.go','utf8').replaceAll('\r\n','\n'),generatedLauncher(catalog));
 assert(selectTests(root,'affected',['tools/copilot/worker.mjs']).some(t=>t.id==='host:copilot_lifecycle'));
 for(const id of ['node:workspace-paths','node:model-capabilities','node:diagnostic-delivery','node:empty-response-retry','host:turn_recovery','host:reliability','host:diagnostics'])assert(selectTests(root,'pi').some(t=>t.id===id),'Pi suite missing '+id);
 assert.equal(selectTests(root,'affected',['README.md']).length,0);
 assert.equal(selectTests(root,'affected',['src/core/game_tools.gd']).length,selectTests(root,'full').length);
 assert.equal(resolveTest(root,'host:opencode_stop').file,'tests/opencode_stop_runner.gd');
 assert.equal(resolveTest(root,'acceptance:windowed').phase,'acceptance');
 assert.throws(()=>resolveTest(root,'host:codex_integration'),/Unknown test/);
 assert.throws(()=>resolveTest(root,'host:../outside'),/Unknown test/);
});
test('shared session persistence and failure records preserve native lifecycle distinctions',t=>{
 const dir=repository(t),path=join(dir,'session.json');atomicSaveSession(path,{session:'first'});atomicSaveSession(path,{session:'second'});
 assert.equal(JSON.parse(readFileSync(path)).session,'second');
 const error=Object.assign(new Error('bad policy'),{initializationFailed:true});
 assert.deepEqual(failureRecord({request:{id:'one'},accepted:false},error),{type:'response',id:'one',success:false,error:'bad policy',initialization_failed:true,runtime_failed:false});
 assert.equal(failureRecord({request:{id:'one'},accepted:true,text:'partial'},error).text,'partial');
});

test('deadlines fail boundedly and preserve diagnostics',async t=>{
 const dir=repository(t);writeFileSync(join(dir,'tests/hang.test.mjs'),"setInterval(()=>{},1000);\n");
 const result=await runVerification(parseArgs(['--test','node:hang','--timeout','800']),dir);
 assert.equal(result.status,'failed');const entry=result.tests.find(t=>t.id==='node:hang');assert.equal(entry.status,'failed');
 assert.match(readFileSync(entry.diagnostics[0].file,'utf8'),/Test deadline exceeded/);
 const progress=JSON.parse(readFileSync(join(result.results_path,'../progress.json')));assert.equal(progress.completed,progress.total);assert.deepEqual(progress.running,[]);
});
test('changes during a run invalidate the evidence',async t=>{
 const dir=repository(t);writeFileSync(join(dir,'tests/mutate.test.mjs'),"import {writeFileSync} from 'node:fs';writeFileSync('changed.json','{}');\n");
 const result=await runVerification(parseArgs(['--test','node:mutate']),dir);
 assert.equal(result.tests[0].status,'passed');assert.equal(result.status,'failed');assert.equal(result.inputs_changed,true);
});

test('missing runtime records setup failure and blocked selections for a focused rerun',async t=>{
 const dir=repository(t),args=['--test','host:test','--godot',join(dir,'missing-godot.exe')];
 const first=await runVerification(parseArgs(args),dir);
 assert.equal(first.status,'failed');assert.equal(first.tests.find(t=>t.id==='setup:godot').status,'failed');assert.equal(first.tests.find(t=>t.id==='host:test').status,'blocked');
 const rerun=await runVerification(parseArgs(['--rerun-failed',first.results_path,'--godot',join(dir,'missing-godot.exe')]),dir);
 assert.deepEqual(rerun.selection,['host:test']);assert.equal(rerun.status,'failed');
});
