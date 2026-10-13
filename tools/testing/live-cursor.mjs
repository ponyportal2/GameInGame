// Restore Cursor's native credential environment without changing Godot's
// isolated APPDATA/user:// directory. Used only by live Windows acceptance.
import {spawn} from 'node:child_process';
import {resolveExecutable} from '../cursor/server.mjs';
const executable=resolveExecutable(process.env.GAMESMITH_TEST_CURSOR_BIN || '');
const child=spawn(executable.bin,[...executable.prefix,...process.argv.slice(2)],{
  env:{...process.env,APPDATA:process.env.GAMESMITH_TEST_NATIVE_APPDATA || process.env.APPDATA},
  windowsHide:true,stdio:'inherit'
});
child.once('error',error=>{console.error(error.message);process.exit(1);});
child.once('exit',code=>process.exit(code ?? 1));
