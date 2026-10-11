import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, writeFileSync, renameSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { createInterface } from 'node:readline';
import { buildArguments, buildConfig, normalizeFrame } from './protocol.mjs';

const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
const emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
let child;
let session=config.session || '';
let contextTokens=config.context_tokens ?? null;
function saveSession() {
  if (!session) return;
  writeFileSync(config.session_file+'.tmp',JSON.stringify({session,context_tokens:contextTokens}));
  renameSync(config.session_file+'.tmp',config.session_file);
}
function executable() {
  const bin=process.env.GAMESMITH_OPENCODE_BIN || 'opencode';
  if (/\.(mjs|js)$/i.test(bin) && existsSync(bin)) return {bin:process.execPath,prefix:[resolve(bin)]};
  if (process.platform !== 'win32') return {bin,prefix:[]};
  const found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd)$/i.test(p));
  if (!found) throw new Error('OpenCode executable was not found. Install opencode or set GAMESMITH_OPENCODE_BIN.');
  if (/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules','opencode-ai','bin','opencode');
  if (!existsSync(entry)) throw new Error('Could not resolve OpenCode npm entry point. Set GAMESMITH_OPENCODE_BIN to its executable.');
  return {bin:process.execPath,prefix:[entry]};
}
createInterface({input:process.stdin}).on('line',line=>{
  let request;
  try { request=JSON.parse(line); } catch { return; }
  if (request.type !== 'prompt' || child) {
    emit({type:'response',id:request.id,success:false,error:'OpenCode is busy or command is unsupported.'}); return;
  }
  try {
    const exe=executable();
    let text=''; let error=''; let finalStepReason='';
    const existing=JSON.parse(process.env.OPENCODE_CONFIG_CONTENT || '{}');
    const host=buildConfig(config);
    const inline={...existing,...host,plugin:[...(existing.plugin || []),...host.plugin],
      instructions:[...(existing.instructions || []),...host.instructions],mcp:{...existing.mcp,...host.mcp}};
    child=spawn(exe.bin,[...exe.prefix,...buildArguments({...config,session},request.message)],{
      cwd:config.workspace,windowsHide:true,stdio:['ignore','pipe','pipe'],
      env:{...process.env,OPENCODE_CONFIG_CONTENT:JSON.stringify(inline),GAMESMITH_HOST_BRIDGE_DIR:config.bridge_dir}});
    child.once('spawn',()=>emit({type:'response',id:request.id,success:true}));
    createInterface({input:child.stdout}).on('line',raw=>{
      try {
        const frame=JSON.parse(raw);
        if (frame.type === 'step_finish') finalStepReason=frame.part?.reason || '';
        for (const record of normalizeFrame(frame)) {
          if (record.session) {session=record.session;saveSession();}
          if (record.type === 'context') {contextTokens=record.tokens;saveSession();}
          if (record.type === 'assistant_text') {text+=record.text;continue;}
          if (record.type === 'integration_error') error=record.error;
          emit(record);
        }
      } catch (e) {error='Invalid OpenCode JSON output: '+e.message;process.stderr.write(error+'\n');}
    });
    child.stderr.pipe(process.stderr,{end:false});
    child.once('error',e=>{error=e.message;emit({type:'response',id:request.id,success:false,error});});
    child.once('close',code=>{
      child=undefined;saveSession();
      emit({type:'complete',ok:code===0 && finalStepReason==='stop' && !error,text,error:error || (code!==0 ? `OpenCode exited with code ${code}.` : finalStepReason!=='stop' ? 'OpenCode exited without a completed response.' : '')});
    });
  } catch (error) {emit({type:'response',id:request.id,success:false,error:error.message});}
});
process.stdin.on('end',()=>{child?.kill();process.exit();});
