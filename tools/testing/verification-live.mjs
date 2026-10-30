import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
// A live run may not rewrite the toolchain it was handed. The probe resolves the
// same executable the adapter launches (override bin, npm shim or native binary)
// so an upgrade to a different install cannot hide behind a PATH alias.
export async function liveVersion(harness,env){
  if(harness!=='cline')return null;
  try{
    const { resolveExecutable } = await import('../cline/server.mjs');
    const { bin, prefix } = resolveExecutable(env.GAMESMITH_CLINE_BIN||undefined);
    const probe = spawnSync(bin,[...prefix,'--version'],{encoding:'utf8',windowsHide:true,env:{...env,CLINE_NO_AUTO_UPDATE:'1'}});
    if(probe.error)return {version:null,command:[bin,...prefix].join(' '),error:probe.error.message};
    const version = (probe.stdout||'').trim().split(/\r?\n/).filter(Boolean).at(-1) || null;
    return {version,command:[bin,...prefix].join(' '),error:version?null:'cline --version printed nothing'};
  }catch(error){return {version:null,command:null,error:error.message};}
}
export function liveEnvironment(harness,env){
  // Native logins live in the real profile. The live host still runs with an
  // isolated HOME, so each harness that reads one has to be told where its
  // credential store is; otherwise it starts logged out.
  if(harness==='cline')return {CLINE_DIR:env.CLINE_DIR||join(homedir(),'.cline')};
  if(harness==='copilot')return {COPILOT_HOME:env.COPILOT_HOME||join(homedir(),'.copilot')};
  if(harness==='omp')return {PI_CODING_AGENT_DIR:env.PI_CODING_AGENT_DIR||join(homedir(),'.omp','agent')};
  if(harness==='crush')return {
    CRUSH_GLOBAL_CONFIG:env.CRUSH_GLOBAL_CONFIG||join(homedir(),'.config','crush'),
    CRUSH_GLOBAL_DATA:env.CRUSH_GLOBAL_DATA||join(env.XDG_DATA_HOME||(process.platform==='win32'?env.LOCALAPPDATA:join(homedir(),'.local','share')),'crush'),
    CRUSH_CACHE_DIR:env.CRUSH_CACHE_DIR||join(env.XDG_CACHE_HOME||(process.platform==='win32'?env.LOCALAPPDATA:join(homedir(),'.cache')),'crush',...(process.platform==='win32'&&!env.XDG_CACHE_HOME?['cache']:[]))};
  return {};
}
