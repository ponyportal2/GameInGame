import { createHash } from 'node:crypto';
import { existsSync, readFileSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

export function atomicJson(path,value){mkdirSync(dirname(path),{recursive:true});writeFileSync(path+'.tmp',JSON.stringify(value,null,2)+'\n');renameSync(path+'.tmp',path);}
export const digest=value=>createHash('sha256').update(value).digest('hex');
export function git(root,args){const r=spawnSync('git',args,{cwd:root,encoding:'utf8',windowsHide:true});if(r.status!==0)throw new Error(r.stderr||'git failed');return r.stdout.trim();}
export function fingerprint(root,tests,runtimes,env=process.env,excluded=[]){
  const files=git(root,['ls-files','--cached','--others','--exclude-standard','-z']).split('\0').filter(Boolean).filter(p=>!excluded.some(dir=>p===dir||p.startsWith(dir+'/'))).filter(p=>/\.(mjs|js|ts|gd|json|cfg|godot|go|mod|sum|py|sh|yml|md|tscn)$/.test(p)||['GameSmith-Windows/GameSmith.pck','GameSmith-Windows/GameSmith.exe'].includes(p)).sort();
  const hash=createHash('sha256');
  for(const p of files){hash.update(p+'\0');hash.update(existsSync(resolve(root,p))?readFileSync(resolve(root,p)):'<deleted>');}
  const dirty_hash=hash.digest('hex');
  // Values are hashed, never included in results; overrides may contain secrets.
  const knobs=Object.fromEntries(Object.entries(env).filter(([k])=>/^(GAMESMITH_|GODOT_|BLENDER_|CI$|NODE_OPTIONS$|PATH$|PYTHONPATH$|KIRO_HOME$|COPILOT_HOME$|PI_CODING_AGENT_DIR$|CRUSH_|XDG_|LANG$|LC_|NPM_CONFIG_)/.test(k)).sort(([a],[b])=>a.localeCompare(b)));
  const revision=git(root,['rev-parse','HEAD']);
  const suite_hash=digest(JSON.stringify(tests));
  return {revision,dirty_hash,suite_hash,fingerprint:digest(JSON.stringify({revision,dirty_hash,suite_hash,runtimes,knobs})),runtimes};
}
// Timing is reported from the same entries the run persisted, so a summary
// never needs a second exhaustive run. Reused and skipped entries carry a
// duration from another process or none at all; ranking them would attribute
// old cost to the current selection.
export function timingSummary(result,limit=5){
  const entries=result.tests||[];
  const spent=prefix=>entries.filter(t=>t.id.startsWith(prefix)).reduce((n,t)=>n+(t.duration_ms||0),0);
  const build=spent('build:'),setup=spent('setup:'),wall=result.duration_ms||0;
  const ran=entries.filter(t=>!t.id.startsWith('build:')&&!t.id.startsWith('setup:')&&['passed','failed'].includes(t.status)&&(t.duration_ms||0)>0);
  const slowest=[...ran].sort((a,b)=>b.duration_ms-a.duration_ms).slice(0,limit);
  const header=`Timing: ${result.suite}, ${(result.selection||[]).length} selected, ${entries.length} entries; wall ${(wall/1000).toFixed(1)}s (build ${(build/1000).toFixed(1)}s, setup ${(setup/1000).toFixed(1)}s, tests ${((wall-build-setup)/1000).toFixed(1)}s)`;
  return slowest.length?header+'\nSlowest: '+slowest.map(t=>`${t.id} ${(t.duration_ms/1000).toFixed(1)}s`).join('; '):header;
}
export function reusedTests(previous,current,key){
  if(previous.fingerprint!==key||previous.status!=='passed')return [];
  return current.map(test=>{
    const old=previous.tests.find(t=>t.id===test.id&&['passed','reused'].includes(t.status));
    return old&&old.log&&existsSync(old.log)?{...old,status:'reused',evidence_from:previous.results_path}:null;
  }).filter(Boolean);
}
export function assertionCounts(text,phase){
  if(phase==='node')return {passed:Number(text.match(/^# pass (\d+)/m)?.[1]||0),failed:Number(text.match(/^# fail (\d+)/m)?.[1]||0),skipped:Number(text.match(/^# skipped (\d+)/m)?.[1]||0)};
  // Godot's push_error prefixes stderr with "ERROR: "; count that form too or a
  // failed host run would report zero failed assertions.
  return {passed:(text.match(/^PASS:/gm)||[]).length,failed:(text.match(/^(?:ERROR: )?FAIL:/gm)||[]).length};
}
// Godot prints a script error with the innermost frame on the next line. Only a
// frame inside the host project proves the runner (or the code it drives) died
// before quit(); several suites deliberately write broken GDScript under user://.
export function fatalScriptError(text){
  return /SCRIPT ERROR:[^\n]*\r?\n\s*at: [^(]*\(res:\/\/(?:src|tests)\//.test(text);
}
export function failureExcerpt(text,maxLines=24){
  const lines=text.split(/\r?\n/);const at=lines.findIndex(l=>/^not ok\b|^(?:ERROR: )?FAIL:|AssertionError|Traceback|^Error:/.test(l));
  const start=at<0?Math.max(0,lines.length-maxLines):Math.max(0,at-2);
  return {start_line:start+1,end_line:Math.min(lines.length,start+maxLines),text:lines.slice(start,start+maxLines).join('\n')};
}
