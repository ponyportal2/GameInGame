// Live acceptance only. Production passes no model/reasoning overrides.
import { spawn } from 'node:child_process';
import { resolveExecutable } from '../codex/server.mjs';
const exe=resolveExecutable(process.env.GAMESMITH_CODEX_LIVE_BIN || 'codex');
const child=spawn(exe.bin,[...exe.prefix,...process.argv.slice(2),'-c','model="gpt-6-luna"','-c','model_reasoning_effort="xhigh"'],
  {windowsHide:true,stdio:'inherit',env:process.env});
child.once('error',error=>{console.error(error.message);process.exit(1);});
child.once('exit',code=>process.exit(code ?? 1));
