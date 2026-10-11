import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('native compaction loads the exact session and sends /compact without a model prompt', async () => {
  const { compactNative } = await import('../tools/command-code/compaction.mjs');
  const dir = await mkdtemp(join(tmpdir(),'gamesmith-compact-test-'));
  const fixture = join(dir,'acp.mjs');
  await writeFile(fixture, `
    import {createInterface} from 'node:readline';
    const emit = value => process.stdout.write(JSON.stringify(value)+'\\n');
    createInterface({input:process.stdin}).on('line',line=>{
      const r=JSON.parse(line);
      if(r.method==='session/load' && r.params.sessionId!=='native-id') process.exit(3);
      if(r.method==='session/prompt') {
        if(r.params.prompt[0].text!=='/compact') process.exit(4);
        if(process.env.FIXTURE_OUTCOME==='crash') process.exit(7);
        if(process.env.FIXTURE_OUTCOME!=='missing') emit({type:'gamesmith_compaction',event:{type:'compaction_outcome',outcome:process.env.FIXTURE_OUTCOME||'summarized',tokensBefore:60000,tokensAfter:25000}});
        emit({jsonrpc:'2.0',method:'session/update',params:{update:{sessionUpdate:'usage_update',used:27000,size:100000}}});
      }
      emit({jsonrpc:'2.0',id:r.id,result:{stopReason:'end_turn'}});
    });
  `);
  const records=[];
  const options={executable:{bin:process.execPath,prefix:[fixture]},workspace:dir,session:'native-id',mod:'observer.ts',onRecord:r=>records.push(r)};
  const result=await compactNative(options);
  assert.equal(result.ok,true);
  assert.equal(result.tokens_before,60000);
  assert.equal(result.tokens_after,27000);
  assert.equal(result.no_op,false);
  assert.ok(records.some(r=>r.type==='context' && r.tokens===27000));
  process.env.FIXTURE_OUTCOME='too-small';
  try { assert.equal((await compactNative(options)).no_op,true); }
  finally { delete process.env.FIXTURE_OUTCOME; }
  process.env.FIXTURE_OUTCOME='failed';
  try { assert.equal((await compactNative(options)).ok,false); }
  finally { delete process.env.FIXTURE_OUTCOME; }
  for (const outcome of ['missing','unexpected','crash']) {
    process.env.FIXTURE_OUTCOME=outcome;
    try { assert.equal((await compactNative(options)).ok,false, outcome+' must not report success'); }
    finally { delete process.env.FIXTURE_OUTCOME; }
  }
});
