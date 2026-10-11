import { writeFile, readFile, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
const argv = process.argv.slice(2);
const prompt = argv[argv.indexOf('--print') + 1];
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
const event = value => emit({type:'event',event:value});
event({type:'run_start',sessionId:'fixture-session'});
async function host(command,args={}) {
  const id = `fixture-${command}`;
  const path = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`request-${id}.json`);
  const response = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`response-${id}.json`);
  await writeFile(path+'.tmp',JSON.stringify({id,command,args}));
  await rename(path+'.tmp',path);
  for (;;) {
    try { const result = JSON.parse(await readFile(response,'utf8')); await rm(response); return result; }
    catch(error) { if(error.code!=='ENOENT') throw error; }
    await new Promise(resolve=>setTimeout(resolve,25));
  }
}
if (prompt === 'reload') {
  await writeFile('main.gd','extends Node\n');
  const result = await host('reload_game');
  if (!result.ok) throw new Error(result.error);
}
if (prompt === 'test') {
  await writeFile('main.gd','extends Node\n');
  const started = await host('start_test_game',{mode:'headless'});
  if (!started.ok) throw new Error(started.error);
  const stopped = await host('stop_test_game',{run_id:started.run_id});
  if (stopped.state !== 'exited') throw new Error('Stop bridge did not wait for confirmed exit');
}
event({type:'text_delta',delta:'Fixture finished'});
emit({type:'result',subtype:'success',stopReason:'end_turn',sessionId:'fixture-session',finalText:'Fixture finished'});
