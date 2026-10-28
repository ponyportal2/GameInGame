import { homedir } from 'node:os';
import { join } from 'node:path';
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
