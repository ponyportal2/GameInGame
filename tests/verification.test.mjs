import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {parseArgs,runVerification} from '../tools/testing/verify.mjs';
import {fingerprint,reusedTests,assertionCounts,failureExcerpt,fatalScriptError} from '../tools/testing/verification-evidence.mjs';
import {selectTests,inventory,resolveTest} from '../tools/testing/verification-plan.mjs';
import {generatedLauncher,exportFilter} from '../tools/testing/generate-harness-inventory.mjs';
import {atomicSaveSession,failureRecord} from '../tools/agent/session-state.mjs';
test('host scheduling bounds audited concurrency and keeps serial barriers',async()=>{
 const {runHostTests}=await import('../tools/testing/verification-plan.mjs');
 assert.equal(typeof runHostTests,'function');
 for(const jobs of [1,2,4]){
  let active=0,peak=0;const completed=[];
  const tests=['host:runtime_properties','host:runtime_node_lifecycle','host:prompt_contract','host:unreviewed','package:contents','live:codex'].map(id=>({id}));
  await runHostTests(tests,jobs,async entry=>{
   const safe=['host:runtime_properties','host:runtime_node_lifecycle','host:prompt_contract'].includes(entry.id);
   if(!safe){assert.equal(active,0);assert.equal(completed.filter(id=>tests.slice(0,3).some(t=>t.id===id)).length,3);}
   active++;peak=Math.max(peak,active);
   await new Promise(resolve=>setTimeout(resolve,5));
   active--;completed.push(entry.id);
  });
  assert.equal(peak,Math.min(jobs,3));assert.deepEqual(completed.slice(-3),['host:unreviewed','package:contents','live:codex']);
  assert.equal(new Set(completed).size,tests.length);
 }
 let stopped=false;const executed=[];
 await runHostTests([{id:'host:runtime_properties'},{id:'host:runtime_node_lifecycle'},{id:'host:unreviewed'}],1,async entry=>{executed.push(entry.id);stopped=true;},()=>stopped);
 assert.deepEqual(executed,['host:runtime_properties']);
 // A failed test result is evidence, not an exception that drops other tests.
 const outcomes=[];
 await runHostTests([{id:'host:runtime_properties'},{id:'host:unreviewed'}],2,async entry=>{outcomes.push(entry.id);return {status:'failed'};});
 assert.equal(outcomes.length,2);
});
const root=resolve('.');
test('affected selection enumerates known consumers and isolates test edits',()=>{
 const ids=paths=>selectTests(root,'affected',paths).map(t=>t.id).sort();
 const check=(paths,expected)=>assert.deepEqual(ids(paths),expected.sort(),paths.join(', '));
 check(['tests/runtime_properties_runner.gd'],['host:runtime_properties','node:verification']);
 check(['tests/runtime_node_lifecycle_runner.gd.uid'],['host:runtime_node_lifecycle','node:verification']);
 check(['tests/tool-output.test.mjs'],['node:tool-output','node:verification']);
 check(['tests/package_contents_runner.gd'],['package:contents','node:verification']);
 check(['src/core/runtime_properties.gd'],['host:runtime_properties','node:runtime-properties','node:tool-output','host:harness_assembly']);
 check(['src/agent/game_prompt.gd'],['host:prompt_contract','host:harness_assembly','node:verification']);
 check(['src/core/game_runner.gd'],['host:cache_edge_regression','host:cache_regression','host:diagnostics','host:game_assets','host:library_actions','host:reliability','host:reload_preflight','host:reload_settings','host:runtime_children','host:runtime_properties','host:script_load_policy','host:test_process','host:test','host:test_workflow','package:contents','host:harness_assembly','node:verification']);
 check(['src/core/game_tools.gd'],['host:runtime_properties','host:reliability','host:reload_preflight','host:reload_settings','host:runtime_children','host:test_process','host:test_workflow','host:workspace_ops','host:blender','host:image_generation','package:contents','host:harness_assembly','node:verification']);
 // Pi is no longer a parent controller: its transport edit selects its own
 // consumers instead of every harness, while the shared base stays exhaustive.
 check(['src/agent/pi_agent_controller.gd'],['host:pi_controller','host:turn_recovery','host:reliability','host:test','host:harness','host:library_actions','host:reload_settings','host:ui_layout','host:blender','host:review_stop','host:chat_history','host:prompt_contract','host:bridge_claim','host:chat_test_process','host:maintenance','host:test_process','node:verification']);
 assert.equal(selectTests(root,'affected',['src/agent/agent_controller_base.gd']).length,selectTests(root,'all').length,'the shared controller base must stay exhaustive');
 check(['src/core/workspace_ops.gd'],['host:workspace_ops','host:runtime_properties','host:reliability','host:blender','package:contents','node:verification']);
 check(['tests/runtime_properties_runner.gd','tests/runtime_properties_runner.gd.uid','tests/verification.test.mjs'],['host:runtime_properties','node:verification']);
 // An unmapped path is exhaustive, never zero and never a guess: an unknown
 // shared file can change behavior in any harness, so narrowing it would let a
 // run pass without the suite that would have caught the change.
 for(const path of ['src/core/unknown.gd','tests/unknown-fixture.gd','tools/testing/verify.mjs','tools/testing/verification-evidence.mjs','tools/testing/assembled-runtime.mjs','src/pi/pi_runtime_config.gd','src/ui/app.gd'])
  assert.deepEqual(ids([path]),selectTests(root,'full').map(t=>t.id).sort(),path);
});
test('host failures are counted and excerpted from Godot error output',()=>{
 const text=['PASS: keeps working','ERROR: FAIL: rejects a workspace link','   at: push_error (core/variant/variant_utility.cpp:1023)','ERROR: FAIL: second failure'].join('\n');
 assert.deepEqual(assertionCounts(text,'host'),{passed:1,failed:2});
 assert.deepEqual(assertionCounts('PASS: plain failure\nFAIL: plain failure\n','host'),{passed:1,failed:1});
 const excerpt=failureExcerpt(text,3);
 assert.equal(excerpt.start_line,1);
 assert.match(excerpt.text,/ERROR: FAIL: rejects a workspace link/);
 assert.deepEqual(assertionCounts('# pass 3\n# fail 1\n# skipped 2\n','node'),{passed:3,failed:1,skipped:2});
 assert.equal(fatalScriptError("SCRIPT ERROR: Invalid access to property or key 'nodes' on a base object of type 'Dictionary'.\n   at: run (res://tests/runtime_properties_runner.gd:36)\n"),true);
 assert.equal(fatalScriptError("SCRIPT ERROR: Cannot call method 'ok' on a null value.\n   at: run (res://src/core/game_runner.gd:214)\n"),true);
 assert.equal(fatalScriptError("SCRIPT ERROR: Parse Error: Expected expression.\n   at: GDScript::reload (user://script-policy-1/bad.gd:3)\n"),false);
 assert.equal(fatalScriptError("ERROR: FAIL: expected rejection\n   at: push_error (core/variant/variant_utility.cpp:1023)\n   at: check (res://tests/x_runner.gd:15)\n"),false);
});
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
 assert(selectTests(root,'affected',['src/core/game_tools.gd']).length<selectTests(root,'core').length);
 assert(selectTests(root,'full').length>selectTests(root,'core').length,'full must stay exhaustive');
 for(const source of ['cline/mcp.mjs','codex/tools.mjs','kiro/mcp.mjs']){
  const selected=new Set(selectTests(root,'affected',['tools/'+source]).map(t=>t.id));
  for(const consumer of catalog.harnesses.filter(h=>h.modules.some(([,file])=>file===source)))
   for(const entry of selectTests(root,consumer.id))assert(selected.has(entry.id),source+' misses '+consumer.id+': '+entry.id);
 }
 for(const parent of ['cline','command_code'])assert.equal(selectTests(root,'affected',['src/agent/'+parent+'_agent_controller.gd']).length,selectTests(root,'all').length,'inherited '+parent+' controller needs broad coverage');
 assert.equal(resolveTest(root,'host:opencode_stop').file,'tests/opencode_stop_runner.gd');
 assert.equal(resolveTest(root,'acceptance:windowed').phase,'acceptance');
 assert.throws(()=>resolveTest(root,'host:codex_integration'),/Unknown test/);
 assert.throws(()=>resolveTest(root,'host:../outside'),/Unknown test/);
});
test('harness coverage defaults to Pi and expands only on an explicit all request',()=>{
 const ids=suite=>new Set(selectTests(root,suite).map(t=>t.id));
 const core=ids('core'),full=ids('full'),all=ids('all'),host=ids('host'),node=ids('node');
 for(const id of ['host:turn_recovery','host:reliability','host:diagnostics','node:workspace-paths','node:model-capabilities','host:harness_assembly'])
  assert(core.has(id),'core surface misses reference coverage '+id);
 for(const id of ['host:copilot_lifecycle','host:cline_lifecycle','host:command_code_lifecycle','node:copilot','node:command-code'])
  assert(!core.has(id),'core surface leaked opt-in harness '+id);
 for(const id of ['host:copilot_lifecycle','host:cline_lifecycle','node:copilot','node:command-code','host:turn_recovery'])
  assert(full.has(id)&&all.has(id),'exhaustive suite misses '+id);
 assert.equal(full.size,all.size,'all is the explicit name for the exhaustive suite');
 // Phase suites are complete selections: run-host-tests.mjs calls --suite host,
 // so a compatibility entry point must not silently drop the opt-in harnesses.
 assert(host.has('host:copilot_lifecycle')&&host.has('host:turn_recovery'));
 assert(node.has('node:copilot')&&node.has('node:workspace-paths'));
 assert.equal(host.size,[...full].filter(id=>id.startsWith('host:')).length,'host must be every host test');
 assert.equal(node.size,[...full].filter(id=>id.startsWith('node:')).length,'node must be every node test');
 assert(ids('copilot').has('host:copilot_lifecycle'),'explicit harness selection still works');
 // The recovery runner is shared but registers one entry per harness: an
 // explicit suite runs only its own scenario, while an edit to the shared
 // source still selects every scenario.
 assert.deepEqual(selectTests(root,'copilot').filter(t=>t.id.startsWith('host:native_recovery')).map(t=>t.id),['host:native_recovery_copilot']);
 assert.equal(selectTests(root,'affected',['tests/native_recovery_runner.gd']).filter(t=>t.id.startsWith('host:native_recovery')).length,13);
 assert.deepEqual(resolveTest(root,'host:native_recovery_copilot').args,['copilot']);
 assert(ids('release').has('host:copilot_lifecycle'),'release remains the comprehensive gate');
 assert([...full].some(id=>!core.has(id)));
});
test('shared session persistence and failure records preserve native lifecycle distinctions',t=>{
 const dir=repository(t),path=join(dir,'session.json');atomicSaveSession(path,{session:'first'});atomicSaveSession(path,{session:'second'});
 assert.equal(JSON.parse(readFileSync(path)).session,'second');
 const error=Object.assign(new Error('bad policy'),{initializationFailed:true});
 assert.deepEqual(failureRecord({request:{id:'one'},accepted:false},error),{type:'response',id:'one',success:false,error:'bad policy',initialization_failed:true,runtime_failed:false});
 assert.equal(failureRecord({request:{id:'one'},accepted:true,text:'partial'},error).text,'partial');
 assert.equal(failureRecord({request:{id:'one'},accepted:true},error,{requestPreserved:false}).request_preserved,false);
 assert.equal(failureRecord({request:{id:'one'},accepted:true},error,{requestPreserved:true}).request_preserved,true);
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
 const rerun=await runVerification(parseArgs(['--rerun-failed',result.results_path]),dir);
 assert.deepEqual(rerun.selection,['node:mutate']);assert.equal(rerun.tests[0].status,'passed');assert.equal(rerun.status,'passed');
});

test('missing runtime records setup failure and blocked selections for a focused rerun',async t=>{
 const dir=repository(t),args=['--test','host:test','--godot',join(dir,'missing-godot.exe')];
 const first=await runVerification(parseArgs(args),dir);
 assert.equal(first.status,'failed');assert.equal(first.tests.find(t=>t.id==='setup:godot').status,'failed');assert.equal(first.tests.find(t=>t.id==='host:test').status,'blocked');
 const rerun=await runVerification(parseArgs(['--rerun-failed',first.results_path,'--godot',join(dir,'missing-godot.exe')]),dir);
 assert.deepEqual(rerun.selection,['host:test']);assert.equal(rerun.status,'failed');
});
