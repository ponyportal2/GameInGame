import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, writeFileSync, renameSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { buildArguments, normalizeFrame } from './protocol.mjs';
import { compactNative } from './compaction.mjs';

const config = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const emit = record => process.stdout.write(JSON.stringify(record) + '\n');
let child;
let session = config.session_id || config.session || '';
let contextTokens = config.context_tokens ?? null;
function sessionPath(id) {
  if (!id || existsSync(id)) return id;
  for (const home of new Set([process.env.HOME, process.env.USERPROFILE, homedir()].filter(Boolean))) {
    const projects = join(home, '.commandcode', 'projects');
    if (!existsSync(projects)) continue;
    for (const project of readdirSync(projects,{withFileTypes:true})) {
      if (!project.isDirectory()) continue;
      const file = join(projects,project.name,`${id}.jsonl`);
      if (existsSync(file)) return file;
    }
  }
  return id;
}
function saveSession(id) {
  if (!id) return;
  session = id;
  writeFileSync(config.session_file + '.tmp', JSON.stringify({session:id,path:sessionPath(id),context_tokens:contextTokens}));
  renameSync(config.session_file + '.tmp', config.session_file);
}
function executable() {
  const bin = process.env.GAMESMITH_COMMAND_CODE_BIN || 'command-code';
  if (existsSync(bin) && /\.(mjs|js)$/i.test(bin)) return {bin:process.execPath,prefix:[resolve(bin)]};
  if (process.platform !== 'win32') return {bin, prefix:[]};
  const found = existsSync(bin) ? resolve(bin) : spawnSync('where.exe', [bin], {encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p => p.endsWith('.cmd'));
  if (!found) throw new Error('Command-code executable was not found. Install command-code or set GAMESMITH_COMMAND_CODE_BIN.');
  if (/\.(mjs|js)$/i.test(found)) return {bin:process.execPath,prefix:[found]};
  if (/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  // npm's Windows shims cannot safely accept arbitrary prompts through cmd.exe.
  const entry = join(dirname(found), 'node_modules', 'command-code', 'dist', 'index.mjs');
  if (!existsSync(entry)) throw new Error('Could not resolve command-code npm entry point beside its shim. Set GAMESMITH_COMMAND_CODE_BIN to dist/index.mjs.');
  return {bin:process.execPath,prefix:[entry]};
}
createInterface({input:process.stdin}).on('line', async line => {
  let request;
  try { request = JSON.parse(line); } catch { return; }
  if (!['prompt','compact'].includes(request.type) || child) {
    emit({type:'response',id:request.id,success:false,error:'Command-code is busy or command is unsupported.'});
    return;
  }
  try {
    const exe = executable();
    if (request.type === 'compact') {
      const result = await compactNative({executable:exe,workspace:config.workspace,session,
        mod:config.compaction_mod,onChild:process => {child=process;},
        onStderr:line => process.stderr.write(line),onRecord:record => {
          if (record.type === 'context') contextTokens = record.tokens;
          emit(record);
        }});
      child = undefined;
      saveSession(session);
      emit({type:'response',id:request.id,success:result.ok,data:result,error:result.error || ''});
      return;
    }
    let completed;
    let integrationError = '';
    child = spawn(exe.bin, [...exe.prefix,...buildArguments({...config,session:sessionPath(session)},request.message)], {
      cwd:config.workspace, windowsHide:true, env:{...process.env,GAMESMITH_HOST_BRIDGE_DIR:config.bridge_dir,GAMESMITH_PROMPT_PATH:config.prompt_path}, stdio:['ignore','pipe','pipe']});
    child.once('spawn', () => emit({type:'response',id:request.id,success:true}));
    createInterface({input:child.stdout}).on('line', raw => {
      try {
        for (const record of normalizeFrame(JSON.parse(raw))) {
          if (record.type === 'context') contextTokens = record.tokens;
          if (record.session) saveSession(record.session);
          if (record.type === 'integration_error') integrationError = record.error;
          if (record.type === 'complete') {
            if (integrationError) { record.ok = false; record.error = integrationError; }
            completed = record;
            continue;
          }
          emit(record);
        }
      } catch (error) { process.stderr.write(`Command-code frame error: ${error.message}\n`); }
    });
    child.stderr.pipe(process.stderr, {end:false});
    child.once('error', error => {
      emit({type:'response',id:request.id,success:false,error:error.message});
    });
    child.once('close', code => {
      child = undefined;
      saveSession(session);
      if (completed) {
        if (code !== 0 && completed.ok) { completed.ok = false; completed.error = `Command-code exited with code ${code}.`; }
        emit(completed);
      } else emit({type:'complete',ok:false,text:'',error:`Command-code exited without a result (code ${code}).`});
    });
  } catch (error) { emit({type:'response',id:request.id,success:false,error:error.message}); }
});
process.stdin.on('end', () => { child?.kill(); process.exit(); });
