import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const HOST_SCRIPTS = ['turn_recovery','native_recovery','game_assets','blender','test','reliability','diagnostics','cache_regression','cache_edge_regression','script_load_policy','test_process','chat_test_process','bridge_claim','maintenance','ui_layout','library_actions','reload_settings','harness','review_ownership','review_stop','command_code_lifecycle','command_code_compaction','opencode_lifecycle','codex_lifecycle','cline_lifecycle','cursor_lifecycle','grok_build_lifecycle','agy_lifecycle','kimi_lifecycle','kiro_lifecycle','kilo_lifecycle','copilot_lifecycle','crush_lifecycle','omp_lifecycle','kilo_stop','agent_shutdown','harness_assembly'];

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
// Explicit and deliberately conservative. Unknown production/test paths select
// everything; no dependency inference can accidentally omit a consumer.
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
    const h=harnesses.find(h=>path.startsWith('tools/'+h.id+'/')||path==='src/agent/'+h.id.replaceAll('-','_')+'_agent_controller.gd');
    // Pi controller and OpenCode transport are inherited by other adapters.
    const isolated=h&&!['pi','opencode'].includes(h.id);
    const subset=isolated?selectTests(root,h.id):tests;
    for(const t of subset)selected.set(t.id,t);
  }
  return [...selected.values()];
}
