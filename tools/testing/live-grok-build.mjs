// Restore native Grok credentials while Godot retains isolated application data.
import {spawn} from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {createInterface} from 'node:readline';
import {resolveExecutable} from '../grok-build/server.mjs';
const exe=resolveExecutable(process.env.GAMESMITH_TEST_GROK_BUILD_BIN || 'grok');
const env={...process.env};
if(env.GAMESMITH_TEST_NATIVE_USERPROFILE){env.USERPROFILE=env.GAMESMITH_TEST_NATIVE_USERPROFILE;env.HOME=env.USERPROFILE;}
const trace=process.env.GAMESMITH_TEST_GROK_TRACE;
const child=spawn(exe.bin,[...exe.prefix,...process.argv.slice(2)],{env,stdio:trace?['pipe','pipe','inherit']:'inherit',windowsHide:true});
if(trace){
  const record=(direction,line)=>{try{const r=JSON.parse(line);if(r.method==='session/request_permission' || r.result?.outcome)appendFileSync(trace,JSON.stringify({direction,...r})+'\n');}catch{}};
  createInterface({input:process.stdin}).on('line',line=>{record('client',line);child.stdin.write(line+'\n');});
  createInterface({input:child.stdout}).on('line',line=>{record('agent',line);process.stdout.write(line+'\n');});
  process.stdin.on('end',()=>child.stdin.end());
}
child.once('error',e=>{console.error(e.message);process.exit(1);});child.once('exit',code=>process.exit(code || 0));
