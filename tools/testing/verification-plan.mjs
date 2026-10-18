import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const HOST_SCRIPTS = ['prompt_contract','runtime_properties','runtime_node_lifecycle','chat_history','image_generation','turn_recovery','native_recovery','game_assets','blender','test','reliability','diagnostics','cache_regression','cache_edge_regression','script_load_policy','test_process','chat_test_process','bridge_claim','maintenance','ui_layout','library_actions','reload_settings','harness','review_ownership','review_stop','command_code_lifecycle','command_code_compaction','opencode_lifecycle','codex_lifecycle','cline_lifecycle','cursor_lifecycle','grok_build_lifecycle','agy_lifecycle','kimi_lifecycle','kiro_lifecycle','kilo_lifecycle','copilot_lifecycle','crush_lifecycle','omp_lifecycle','kilo_stop','agent_shutdown','harness_assembly'];

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
};

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
  const tests=allTests(root), harnesses=inventory(root);
  if(suite==='release')return [...tests,...RELEASE_TESTS];
  if(suite==='acceptance')return RELEASE_TESTS;
  if(suite==='smoke')return tests.filter(t=>['node:verification','host:harness_assembly','host:test','host:library_actions'].includes(t.id));
  if(suite==='full')return tests;
  if(['node','host','package','launcher'].includes(suite))return tests.filter(t=>t.phase===suite);
  const harness=harnesses.find(h=>h.id===suite);
  if(harness)return tests.filter(t=>harness.node_suites.includes(t.file)||harness.host_runners.includes(t.file)||['host:harness','host:harness_assembly','host:native_recovery'].includes(t.id));
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
    const subset=consumers.length&&!inherited?consumers.flatMap(h=>selectTests(root,h.id)):tests;
    for(const t of subset)selected.set(t.id,t);
  }
  return [...selected.values()];
}
