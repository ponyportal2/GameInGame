import {test} from 'node:test';
import assert from 'node:assert/strict';
import {CrushStream} from '../tools/crush/protocol.mjs';

const message=(id,text,extra=[])=>({id,session_id:'session',role:'assistant',parts:[{type:'text',data:{text}},...extra]});
test('Crush snapshots stream once; tool-use finish is not turn completion',()=>{
  const stream=new CrushStream('session','run',['old']);
  assert.deepEqual(stream.message(message('old','stale')),[]);
  assert.deepEqual(stream.message({...message('foreign','bad'),session_id:'other'}),[]);
  assert.equal(stream.message(message('a','Hi'))[0].text,'Hi');
  assert.deepEqual(stream.message(message('a','Hi')),[]);
  assert.equal(stream.message(message('a','Hi there'))[0].text,' there');
  assert.deepEqual(stream.message(message('a','Hi there',[{type:'finish',data:{reason:'tool_use'}}])),[]);
  assert.equal(stream.complete({session_id:'session',run_id:'foreign',text:'bad'}),null);
  assert.equal(stream.complete({session_id:'foreign',run_id:'run',text:'bad'}),null);
  const final=stream.complete({session_id:'session',run_id:'run',message_id:'a',text:'Hi there!'});
  assert.equal(final.text,'Hi there!');assert.equal(final.records[0].text,'!');assert.equal(final.ok,true);
});
test('Crush final completion repairs missed events and preserves earlier assistant rounds',()=>{
  const stream=new CrushStream('session','run');
  stream.message(message('a','Checking.'));
  stream.message(message('b','Fixed'));
  const final=stream.complete({session_id:'session',run_id:'run',message_id:'b',text:'Fixed movement.'});
  assert.equal(final.text,'Checking.Fixed movement.');assert.equal(final.records[0].text,' movement.');
  const missed=new CrushStream('session','run').complete({session_id:'session',run_id:'run',message_id:'z',text:'Done'});
  assert.equal(missed.text,'Done');assert.equal(missed.records[0].text,'Done');
});
test('Crush thinking and tool announcements deduplicate without exposing tool results as prose',()=>{
  const stream=new CrushStream('session','run');
  const m=message('a','',[{type:'reasoning',data:{thinking:'Thinking'}},{type:'tool_call',data:{id:'call',name:'mcp_gamesmith_write',input:'{}',finished:true}}]);
  assert.deepEqual(stream.message(m).map(r=>r.type),['delta','tool']);
  assert.deepEqual(stream.message(m),[]);
  assert.deepEqual(stream.message({...m,role:'tool'}),[]);
  assert.equal(stream.complete({session_id:'session',run_id:'run',message_id:'a',error:'provider failed'}).ok,false);
  assert.equal(stream.complete({session_id:'session',run_id:'run',message_id:'a',cancelled:true}).ok,false);
});
