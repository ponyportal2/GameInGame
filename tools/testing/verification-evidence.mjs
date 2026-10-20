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
export function failureExcerpt(text,maxLines=24){
  const lines=text.split(/\r?\n/);const at=lines.findIndex(l=>/^not ok\b|^(?:ERROR: )?FAIL:|AssertionError|Traceback|^Error:/.test(l));
  const start=at<0?Math.max(0,lines.length-maxLines):Math.max(0,at-2);
  return {start_line:start+1,end_line:Math.min(lines.length,start+maxLines),text:lines.slice(start,start+maxLines).join('\n')};
}
