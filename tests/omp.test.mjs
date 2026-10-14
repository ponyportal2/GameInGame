import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {resolveExecutable,launchArgs} from '../tools/omp/server.mjs';
import policy from '../tools/omp/policy.mjs';

test('OMP resolution never selects Pi or generic agent',()=>{
  assert.deepEqual(resolveExecutable('omp','linux'),{bin:'omp',prefix:[]});
  const bin=join(mkdtempSync(join(tmpdir(),'gs-omp-')),'omp.exe');writeFileSync(bin,'fixture');
  assert.deepEqual(resolveExecutable(bin,'win32'),{bin,prefix:[]});
  assert.deepEqual(resolveExecutable(resolve('tools/testing/fake-omp.mjs')),{bin:process.execPath,prefix:[resolve('tools/testing/fake-omp.mjs')]});
});
test('launch disables native tools/discovery and resumes only the explicit private file',()=>{
  const args=launchArgs({nativeRoot:'C:/private',session:'history.jsonl',prompt_path:'prompt.md',policy:'policy.mjs',overlay:'config.yml'});
  for(const flag of ['--mode','rpc','--no-tools','--no-extensions','--no-skills','--no-rules','--no-lsp','--no-title','--no-ui','--resume'])assert(args.includes(flag));
  assert(args.includes(join('C:/private','sessions','history.jsonl')));
  assert(!args.some(a=>['--model','--thinking','--provider','--continue','--profile'].includes(a)));
  assert.throws(()=>launchArgs({session:'../escape.jsonl'}),/session reference/);
});
test('policy readiness verifies exact active tools and guard failures deny execution',async()=>{
  const root=mkdtempSync(join(tmpdir(),'gs-omp-policy-')),record=join(root,'policy.json');
  const old=process.env.GAMESMITH_OMP_POLICY;
  process.env.GAMESMITH_OMP_POLICY=JSON.stringify({nonce:'fresh',path:record,tools:['gamesmith_read','gamesmith_write']});
  try{
    const hooks={},commands={};let active=['bash'];
    await policy({on:(n,f)=>hooks[n]=f,registerCommand:(n,c)=>commands[n]=c,setActiveTools:async names=>{active=names;},getActiveTools:()=>active});
    await commands['gamesmith-ready'].handler();
    assert.deepEqual(JSON.parse(readFileSync(record,'utf8')),{nonce:'fresh',tools:['gamesmith_read','gamesmith_write']});
    assert.deepEqual(await hooks.tool_call({toolName:'bash'}),{block:true,reason:'Only GameSmith host tools are available.'});
    assert.equal(await hooks.tool_call({toolName:'gamesmith_write'}),undefined);
    assert.equal((await hooks.tool_call(null)).block,true);
    active=['bash'];await hooks.before_agent_start();assert.deepEqual(active,['gamesmith_read','gamesmith_write']);
  }finally{if(old===undefined)delete process.env.GAMESMITH_OMP_POLICY;else process.env.GAMESMITH_OMP_POLICY=old;}
});
