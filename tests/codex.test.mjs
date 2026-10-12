import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, mkdir, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { threadParams, createEventNormalizer } from '../tools/codex/protocol.mjs';
import { toolSpecs, executeTool } from '../tools/codex/tools.mjs';

test('Codex thread inherits native settings and resumes only the game thread', () => {
  const config={workspace:'/game',session:'game-thread'};
  const params=threadParams(config,'instructions');
  assert.equal(params.threadId,'game-thread');
  for (const key of ['model','modelProvider','effort','serviceTier']) assert.equal(Object.hasOwn(params,key),false);
  assert.equal(params.sandbox,'read-only');
  assert.equal(params.approvalPolicy,'on-request');
  assert.equal(Object.hasOwn(params,'dynamicTools'),false);
  const fresh=threadParams({...config,session:''},'instructions');
  assert.ok(fresh.dynamicTools.some(t=>t.name==='gamesmith_reload_game'));
  assert.ok(fresh.dynamicTools.some(t=>t.name==='gamesmith_write'));
  assert.equal(fresh.config.features.shell_tool,false);
  assert.equal(fresh.config.features.multi_agent,false);
});

test('Codex final items repair partial deltas and do not duplicate commentary', () => {
  const normalize=createEventNormalizer('thread','turn');
  assert.deepEqual(normalize('item/agentMessage/delta',{threadId:'other',turnId:'turn',itemId:'a',delta:'wrong'}),[]);
  assert.equal(normalize('item/agentMessage/delta',{threadId:'thread',turnId:'turn',itemId:'a',delta:'Working.'})[0].text,'Working.');
  normalize('item/completed',{threadId:'thread',turnId:'turn',item:{id:'a',type:'agentMessage',text:'Working.',phase:'commentary'}});
  normalize('item/agentMessage/delta',{threadId:'thread',turnId:'turn',itemId:'b',delta:'Done'});
  const completed=normalize('turn/completed',{threadId:'thread',turn:{id:'turn',status:'completed',items:[{id:'a',type:'agentMessage',text:'Working.',phase:'commentary'},{id:'b',type:'agentMessage',text:'Done correctly.',phase:'final_answer'}]}});
  assert.equal(completed.find(r=>r.type==='delta').text,' correctly.');
  assert.equal(completed.at(-1).text,'Working.\n\nDone correctly.');
  assert.equal(completed.at(-1).ok,true);
  assert.equal(completed.at(-1).corrected,false);
});

test('Codex errors, interruption and current context usage remain distinct', () => {
  const normalize=createEventNormalizer('thread','turn');
  assert.equal(normalize('thread/tokenUsage/updated',{threadId:'thread',tokenUsage:{last:{totalTokens:123},total:{totalTokens:999}}})[0].tokens,123);
  assert.equal(normalize('turn/completed',{threadId:'thread',turn:{id:'turn',status:'failed',error:{message:'provider failed'},items:[]}}).at(-1).error,'provider failed');
  assert.equal(normalize('turn/completed',{threadId:'thread',turn:{id:'turn',status:'interrupted',items:[]}}).at(-1).ok,false);
  assert.equal(normalize('item/completed',{threadId:'thread',turnId:'turn',item:{type:'dynamicToolCall',id:'tool'}})[0].type,'status');
});

test('Codex canonical answer corrects conflicting text and separates unstreamed items',()=>{
  const normalize=createEventNormalizer('thread','turn');
  normalize('item/agentMessage/delta',{threadId:'thread',turnId:'turn',itemId:'a',delta:'old'});
  normalize('item/completed',{threadId:'thread',turnId:'turn',item:{id:'a',type:'agentMessage',text:'correct'}});
  const records=normalize('turn/completed',{threadId:'thread',turn:{id:'turn',status:'completed',items:[{id:'b',type:'agentMessage',text:'Final.'}]}});
  assert.equal(records[0].text,'\n\nFinal.');
  assert.equal(records.at(-1).text,'correct\n\nFinal.');assert.equal(records.at(-1).corrected,true);
});

test('bounded Codex file tools reject traversal, .git writes, ambiguous edits and linked escapes', async () => {
  const workspace=await mkdtemp(join(tmpdir(),'gamesmith-codex-tools-'));
  const config={workspace};
  assert.ok(toolSpecs().every(t=>t.name.startsWith('gamesmith_')));
  assert.equal((await executeTool(config,'gamesmith_write',{path:'dir/main.gd',content:'one\none\nthree'})).ok,true);
  const read=await executeTool(config,'gamesmith_read',{path:'dir/main.gd',offset:2,limit:1});
  assert.equal(read.text,'one'); assert.equal(read.truncated,true);
  await assert.rejects(executeTool(config,'gamesmith_edit',{path:'dir/main.gd',old_text:'one',new_text:'two'}),/ambiguous/i);
  assert.equal((await readFile(join(workspace,'dir/main.gd'),'utf8')),'one\none\nthree');
  await executeTool(config,'gamesmith_edit',{path:'dir/main.gd',old_text:'three',new_text:'four'});
  for (const path of ['../outside','/absolute','.git/config']) await assert.rejects(executeTool(config,'gamesmith_write',{path,content:'bad'}));
  const outside=await mkdtemp(join(tmpdir(),'codex-outside-'));await writeFile(join(outside,'secret'),'outside');
  await symlink(outside,join(workspace,'linked'),process.platform==='win32'?'junction':'dir');
  await assert.rejects(executeTool(config,'gamesmith_read',{path:'linked/secret'}));
  const list=await executeTool(config,'gamesmith_list',{path:'.'});
  assert.ok(list.entries.includes('dir/'));assert.ok(!list.entries.includes('linked/secret'));
  assert.equal((await executeTool(config,'gamesmith_search',{pattern:'four'})).matches[0].path,'dir/main.gd');
  await executeTool(config,'gamesmith_write',{path:'pages.txt',content:'a'.repeat(20000)+'\n'+'b'.repeat(20000)});
  const page=await executeTool(config,'gamesmith_read',{path:'pages.txt'});
  assert.equal(page.next_offset,2);assert.equal(page.truncated,true);
  assert.equal((await executeTool(config,'gamesmith_read',{path:'pages.txt',offset:page.next_offset})).text,'b'.repeat(20000));
});
