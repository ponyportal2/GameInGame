import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

// Print mode treats /compact as model input. ACP executes the native command.
export async function compactNative({executable, workspace, session, mod, onChild, onRecord = () => {}, onStderr = () => {}}) {
  if (!session) return {ok:false,no_op:true,error:'No saved Command-code conversation to compact.'};
  // ACP 1.79 ignores --mod. Its user drop-in loader works; this observer is
  // inert outside this explicitly marked compaction subprocess.
  if (mod && existsSync(mod)) {
    const directory = join(process.env.HOME || process.env.USERPROFILE || homedir(), '.commandcode', 'mods');
    mkdirSync(directory, {recursive:true});
    const target = join(directory, 'gamesmith-compaction-observer-v2.ts');
    const source = readFileSync(mod, 'utf8').replace(/\r\n/g, '\n');
    try { writeFileSync(target, source, {flag:'wx'}); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (readFileSync(target, 'utf8').replace(/\r\n/g, '\n') !== source) return {ok:false,error:'Existing GameSmith compaction observer differs; refusing to overwrite it.'};
    }
  }
  const child = spawn(executable.bin, [...executable.prefix, '--no-auto-update', '--skip-onboarding', '--no-skills', '--mod', mod, 'acp'],
    {cwd:workspace, windowsHide:true, env:{...process.env,GAMESMITH_COMPACTION_OBSERVER:'gamesmith-v2'}, stdio:['pipe','pipe','pipe']});
  onChild?.(child);
  let nextId = 0, outcome, context;
  const pending = new Map();
  let closed = false;
  const completion = new Promise(resolve => {
    child.once('error', error => {
      for (const request of pending.values()) request.reject(error);
    });
    child.once('close', code => {
      closed = true;
      for (const request of pending.values()) request.reject(new Error(`Command-code compaction process exited (code ${code}).`));
      pending.clear();
      resolve(code);
    });
  });
  child.stderr.on('data', data => onStderr(data.toString()));
  child.stdin.on('error', error => { for (const request of pending.values()) request.reject(error); });
  createInterface({input:child.stdout}).on('line', line => {
    let frame;
    try { frame = JSON.parse(line); } catch { return; }
    if (frame.type === 'gamesmith_compaction') {
      const event = frame.event;
      if (event.type === 'compaction_outcome') outcome = event;
      if (event.type === 'compaction_start') onRecord({type:'status',text:'Command-code is compacting context…'});
      return;
    }
    if (frame.method === 'session/update' && frame.params?.update?.sessionUpdate === 'usage_update') {
      context = frame.params.update.used;
      return;
    }
    if (frame.method && frame.id !== undefined) {
      // Compaction needs no player-facing permissions or client filesystem services.
      child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:frame.id,error:{code:-32601,message:'Client method unavailable during compaction.'}})+'\n');
      return;
    }
    const request = pending.get(frame.id);
    if (!request) return;
    pending.delete(frame.id);
    if (frame.error) request.reject(new Error(frame.error.message));
    else request.resolve(frame.result);
  });
  const request = (method, params) => new Promise((resolve,reject) => {
    if (closed) return reject(new Error('Command-code compaction process has stopped.'));
    const id = ++nextId;
    pending.set(id,{resolve,reject});
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');
  });
  let result;
  try {
    await request('initialize',{protocolVersion:1,clientCapabilities:{},clientInfo:{name:'gamesmith',version:'1'}});
    await request('session/load',{sessionId:session,cwd:workspace,mcpServers:[]});
    await request('session/prompt',{sessionId:session,prompt:[{type:'text',text:'/compact'}]});
    if (!outcome) throw new Error('Command-code did not report a native compaction outcome.');
    if (!['summarized','too-small','failed'].includes(outcome.outcome)) throw new Error('Unknown native compaction outcome: ' + outcome.outcome);
    const noOp = outcome.outcome === 'too-small';
    result = {ok:outcome.outcome !== 'failed',no_op:noOp,tokens_before:outcome.tokensBefore,tokens_after:context ?? null,
      error:outcome.outcome === 'failed' ? 'Native Command-code summarization failed; history was kept.' : noOp ? 'Conversation is too small to compact.' : ''};
    if (result.ok && Number.isFinite(context)) onRecord({type:'context',tokens:context});
    await request('session/close',{sessionId:session});
  } catch (error) {
    result = {ok:false,error:error.message};
    child.kill();
  } finally {
    child.stdin.end();
  }
  const code = await completion;
  if (code !== 0 && result.ok) return {ok:false,error:`Command-code compaction process exited (code ${code}).`};
  return result;
}
