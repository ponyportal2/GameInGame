import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..'),templates=new Map();
process.once('exit',()=>{for(const template of templates.values())rmSync(template,{recursive:true,force:true});});
export function assembleHarnessRuntime(harness,destination){
  if(!templates.has(harness)){
    const template=mkdtempSync(join(tmpdir(),'gamesmith-runtime-'+harness+'-'));
    const godot=process.env.GODOT_BIN||resolve(root,'GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe');
    const r=spawnSync(godot,['--headless','--path',root,'--script','res://tools/testing/assemble-runtime.gd','--',harness,template],{encoding:'utf8',windowsHide:true,timeout:30000});
    if(r.status!==0)throw new Error('Runtime assembly failed: '+(r.error?.message||r.stdout+r.stderr));
    templates.set(harness,template);
  }
  cpSync(templates.get(harness),destination,{recursive:true});
  return destination;
}
