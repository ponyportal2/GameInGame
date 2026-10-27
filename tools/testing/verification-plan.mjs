import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const HOST_SCRIPTS = ['test_supervisor_exit','test_workflow','runtime_children','reload_preflight','prompt_contract','runtime_properties','runtime_node_lifecycle','chat_history','workspace_store','image_generation','turn_recovery','native_recovery','game_assets','blender','test','reliability','diagnostics','cache_regression','cache_edge_regression','script_load_policy','test_process','chat_test_process','bridge_claim','maintenance','ui_layout','library_actions','reload_settings','harness','review_ownership','review_stop','command_code_lifecycle','command_code_compaction','opencode_lifecycle','codex_lifecycle','cline_lifecycle','cursor_lifecycle','grok_build_lifecycle','agy_lifecycle','kimi_lifecycle','kiro_lifecycle','kilo_lifecycle','copilot_lifecycle','crush_lifecycle','omp_lifecycle','kilo_stop','agent_shutdown','harness_assembly'];

export function inventory(root) {
  return JSON.parse(readFileSync(resolve(root,'tools/agent/harnesses.json'),'utf8')).harnesses;
}
export function allTests(root) {
  const node = readdirSync(resolve(root,'tests')).filter(f=>f.endsWith('.test.mjs')).sort().map(file=>({id:'node:'+file.replace('.test.mjs',''),phase:'node',file:'tests/'+file}));
  return [...node,...HOST_SCRIPTS.map(name=>({id:'host:'+name,phase:'host',file:'tests/'+name+'_runner.gd'})),
    {id:'package:structure',phase:'package',file:'tools/testing/verify_windows_package.py'},
    {id:'package:contents',phase:'package',file:'tests/package_contents_runner.gd'},
    {id:'launcher:unit',phase:'launcher',file:'tools/windows-bootstrap'}];
}
// Audited inputs only. Configuration/lifecycle files not listed here retain the
// full fallback. Prompt text has its own file so that boundary is unambiguous.
export const INPUT_CONSUMERS = {
  'src/core/runtime_properties.gd': ['host:runtime_properties','node:runtime-properties','node:tool-output','host:harness_assembly'],
  'src/agent/game_prompt.gd': ['host:prompt_contract','host:harness_assembly','node:verification'],
  'tests/runtime_wall_response.gd': ['node:runtime-properties','node:verification'],
  // Hot core files. A preload search is not a consumer graph, so each list was
  // audited by behavior: every suite that preloads the file plus every suite
  // that drives the run/reload path or calls the tool facade and asserts on its
  // result. Suites that only start a game as scaffolding for another subject are
  // excluded; they still run in `full` and `release`. A new suite that asserts
  // on this behavior must be added here or it silently loses affected coverage.
  'src/core/game_runner.gd': ['host:cache_edge_regression','host:cache_regression','host:diagnostics','host:game_assets','host:reliability','host:reload_preflight','host:reload_settings','host:runtime_children','host:runtime_properties','host:script_load_policy','host:test_process','host:test','host:test_workflow','host:library_actions','package:contents','host:harness_assembly','node:verification'],
  'src/core/game_tools.gd': ['host:runtime_properties','host:reliability','host:reload_preflight','host:reload_settings','host:runtime_children','host:test','host:test_process','host:test_workflow','host:blender','host:image_generation','package:contents','host:harness_assembly','node:verification'],
};

// The reference harness stays in every broad run. The other thirteen suites
// cost minutes each, so `core` keeps only Pi; `full`/`all`, `release` and the
// phase suites stay exhaustive, and an affected change that names a harness
// still selects that harness.
export const REFERENCE_HARNESS = 'pi';
const SHARED_HARNESS_TESTS = new Set(['host:harness','host:harness_assembly','host:native_recovery']);
function defaultSurface(tests,harnesses) {
  return tests.filter(t=>{
    const owners=harnesses.filter(h=>h.node_suites.includes(t.file)||h.host_runners.includes(t.file));
    return !owners.length||owners.some(h=>h.id===REFERENCE_HARNESS);
  });
}

// Each allowlisted runner was audited for writes outside isolated user://,
// subprocesses, ports and global CLI state. Package/process/lifecycle suites
// remain serial. See docs/todos/verification-speed.md for the audit.
export const PARALLEL_SAFE_HOSTS = new Set(['host:runtime_properties','host:runtime_node_lifecycle','host:harness_assembly','host:prompt_contract']);

export async function runHostTests(tests,jobs,run,stopped=()=>false) {
  const safe=tests.filter(t=>PARALLEL_SAFE_HOSTS.has(t.id));
  let next=0;
  await Promise.all(Array.from({length:Math.min(jobs,safe.length)},async()=>{
    while(next<safe.length&&!stopped())await run(safe[next++]);
  }));
  // No serial test overlaps even an audited runner: those suites may touch
  // shared project files, processes, ports or native CLI configuration.
  for(const test of tests.filter(t=>!PARALLEL_SAFE_HOSTS.has(t.id))){
    if(stopped())break;
    await run(test);
  }
}
export const RELEASE_TESTS=[{id:'acceptance:pi-emulator',phase:'acceptance',file:'tools/testing/run-pi-e2e.mjs'},{id:'acceptance:migration',phase:'acceptance',file:'tools/testing/verify-migration.mjs'},{id:'acceptance:windowed',phase:'acceptance',file:'tests/windowed_input_runner.gd'}];

export function resolveTest(root,id) {
  const known=[...allTests(root),...RELEASE_TESTS].find(t=>t.id===id);
  if(known)return known;
  // Preserve the old host entrypoint's explicit auxiliary-runner support.
  // Model acceptance must still pass through --live and its Codex guard.
  if(/^host:[a-z][a-z0-9_]*$/.test(id)&&!id.endsWith('_integration')) {
    const file='tests/'+id.slice(5)+'_runner.gd';
    if(existsSync(resolve(root,file)))return {id,phase:'host',file};
  }
  throw new Error('Unknown test: '+id);
}

export function selectTests(root,suite='full',changed=[]) {
  const tests=allTests(root), harnesses=inventory(root), core=defaultSurface(tests,harnesses);
  // `full` keeps its historical meaning: every discovered deterministic test.
  // The cheaper Pi-centric surface has its own name so no suite lies about scope.
  if(suite==='full'||suite==='all')return tests;
  if(suite==='core')return core;
  // Phase suites are complete selections. `run-host-tests.mjs` calls `--suite
  // host`, and a compatibility entry point must not quietly drop the thirteen
  // opt-in harness suites; only `core` is allowed to mean "the narrow surface".
  if(['node','host','package','launcher'].includes(suite))return tests.filter(t=>t.phase===suite);
  // Release is the deliberate pre-release gate, so it keeps every harness.
  if(suite==='release')return [...tests,...RELEASE_TESTS];
  if(suite==='acceptance')return RELEASE_TESTS;
  if(suite==='smoke')return tests.filter(t=>['node:verification','host:harness_assembly','host:test','host:library_actions'].includes(t.id));
  const harness=harnesses.find(h=>h.id===suite);
  if(harness)return tests.filter(t=>harness.node_suites.includes(t.file)||harness.host_runners.includes(t.file)||SHARED_HARNESS_TESTS.has(t.id));
  if(suite!=='affected')throw new Error('Unknown suite: '+suite);
  const selected=new Map();
  for(const path of changed){
    if(/\.(md|png|jpg|zip)$/.test(path)&&!path.startsWith('tools/blender/'))continue;
    const source=path.endsWith('.gd.uid')?path.slice(0,-4):path;
    const ownTest=tests.find(t=>t.file===source);
    const explicit=INPUT_CONSUMERS[source];
    if(ownTest||explicit){
      const ids=ownTest?[ownTest.id,'node:verification']:explicit;
      // Missing catalog entries are a configuration error, never a quiet omission.
      for(const id of ids){const test=tests.find(t=>t.id===id);if(!test)throw new Error('Missing affected consumer: '+id);selected.set(id,test);}
      continue;
    }
    const consumers=harnesses.filter(h=>path.startsWith('tools/'+h.id+'/')||path===h.controller||h.modules.some(([,source])=>path==='tools/'+source));
    // These controllers own inherited lifecycle behavior, not just one harness.
    // Keep this explicit rather than guessing GDScript dependencies.
    const inherited=['pi','command_code','opencode','cline'].some(id=>path==='src/agent/'+id+'_agent_controller.gd');
    // A changed shared module or inherited controller keeps every consumer. An
    // unmapped path is exhaustive: an unknown shared file can change behavior in
    // any harness, and a narrower guess would let SoftFac pass without running
    // the suite that would have caught it.
    const subset=inherited||!consumers.length?tests:consumers.flatMap(h=>selectTests(root,h.id));
    for(const t of subset)selected.set(t.id,t);
  }
  return [...selected.values()];
}
