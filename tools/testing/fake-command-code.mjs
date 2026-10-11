import { writeFile, readFile, rename, rm, appendFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { join } from 'node:path';
const argv = process.argv.slice(2);
if (argv.includes('acp')) {
  createInterface({input:process.stdin}).on('line',async line => {
    const r=JSON.parse(line);
    const emit=v=>process.stdout.write(JSON.stringify(v)+'\n');
    if(r.method==='session/load' && r.params.sessionId!=='fixture-session') process.exit(3);
    if(r.method==='session/prompt') {
      if(r.params.prompt[0].text!=='/compact') process.exit(4);
      await appendFile('.compaction-fixture.jsonl',JSON.stringify({session:r.params.sessionId,pid:process.pid})+'\n');
      emit({type:'gamesmith_compaction',event:{type:'compaction_start'}});
      const outcome=process.env.GAMESMITH_FAKE_COMPACTION || 'summarized';
      if(outcome==='slow') return;
      emit({type:'gamesmith_compaction',event:{type:'compaction_outcome',outcome,tokensBefore:65020}});
      emit({method:'session/update',params:{update:{sessionUpdate:'usage_update',used:25000}}});
    }
    emit({jsonrpc:'2.0',id:r.id,result:{}});
  });
} else {
const prompt = argv[argv.indexOf('--print') + 1];
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
const event = value => emit({type:'event',event:value});
event({type:'run_start',sessionId:'fixture-session'});
async function host(command,args={}) {
  event({type:'tool_running',toolName:command});
  const id = `fixture-${command}`;
  const path = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`request-${id}.json`);
  const response = join(process.env.GAMESMITH_HOST_BRIDGE_DIR,`response-${id}.json`);
  await writeFile(path+'.tmp',JSON.stringify({id,command,args}));
  await rename(path+'.tmp',path);
  for (;;) {
    try { const result = JSON.parse(await readFile(response,'utf8')); await rm(response); event({type:result.ok === false ? 'tool_errored' : 'tool_completed',toolName:command}); return result; }
    catch(error) { if(error.code!=='ENOENT') throw error; }
    await new Promise(resolve=>setTimeout(resolve,25));
  }
}
if (prompt === 'repair-reload') {
  await writeFile('main.gd','extends Node\nfunc broken(:\n');
  const failed = await host('reload_game');
  if (failed.ok || !failed.error || !failed.diagnostics) throw new Error('Missing actionable reload failure');
  await writeFile('main.gd','extends Node\nvar repaired = true\n');
  const tested = await host('start_test_game',{mode:'headless'});
  if (!tested.ok) throw new Error(tested.error);
  await host('read_test_log',{run_id:tested.run_id});
  await host('stop_test_game',{run_id:tested.run_id});
  const loaded = await host('reload_game');
  if (!loaded.ok) throw new Error(loaded.error);
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
event({type:'model_request_end',usage:{inputTokens:prompt==='large-context'?60000:100,cacheReadTokens:5000,outputTokens:20}});
emit({type:'result',subtype:'success',stopReason:'end_turn',sessionId:'fixture-session',finalText:'Fixture finished'});
}
