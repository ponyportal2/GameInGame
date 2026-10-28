import test from 'node:test';
import assert from 'node:assert/strict';
import { createAcpNormalizer, createEventNormalizer } from '../tools/opencode/events.mjs';

const event=(type,properties)=>({type,properties});
const part=(type,id='p',extra={})=>({sessionID:'s',messageID:'m',id,type,...extra});

test('reasoning and assistant deltas appear before the part completes without duplicate final text',()=>{
  const normalize=createEventNormalizer('s');
  normalize(event('message.updated',{info:{id:'m',sessionID:'s',role:'assistant'}}));
  normalize(event('message.part.updated',{part:part('reasoning','r',{text:'',time:{start:1}})}));
  assert.deepEqual(normalize(event('message.part.delta',{sessionID:'s',partID:'r',field:'text',delta:'Thinking now'})),[{type:'delta',kind:'thinking',text:'Thinking now'}]);
  assert.deepEqual(normalize(event('message.part.updated',{part:part('reasoning','r',{text:'Thinking now',time:{start:1,end:2}})})),[]);
  normalize(event('message.part.updated',{part:part('text','t',{text:'',time:{start:1}})}));
  assert.deepEqual(normalize(event('message.part.delta',{sessionID:'s',partID:'t',field:'text',delta:'Hello'})),[{type:'delta',kind:'assistant',text:'Hello'},{type:'assistant_text',text:'Hello'}]);
  assert.deepEqual(normalize(event('message.part.updated',{part:part('text','t',{text:'Hello!',time:{start:1,end:2}})})),[{type:'delta',kind:'assistant',text:'!'},{type:'assistant_text',text:'!'}]);
});

test('user input and events from other sessions never become assistant output',()=>{
  const normalize=createEventNormalizer('s');
  normalize(event('message.updated',{info:{id:'m',sessionID:'s',role:'user'}}));
  assert.deepEqual(normalize(event('message.part.updated',{part:part('text','u',{text:'player input'})})),[]);
  assert.deepEqual(normalize(event('message.part.delta',{sessionID:'s',partID:'u',field:'text',delta:'input'})),[]);
  assert.deepEqual(normalize(event('message.part.updated',{part:{...part('reasoning'),sessionID:'other',text:'secret',time:{end:2}}})),[]);
});

test('running tools appear immediately and repeated updates do not repeat activity',()=>{
  const normalize=createEventNormalizer('s');
  const running=event('message.part.updated',{part:part('tool','tool',{tool:'read',state:{status:'running',title:'main.gd'}})});
  assert.equal(normalize(running)[0].type,'tool');
  assert.deepEqual(normalize(running),[]);
  assert.equal(normalize(event('message.part.updated',{part:part('tool','tool',{tool:'read',state:{status:'completed'}})}))[0].type,'tool');
});

test('final reconciliation fills only the final message suffix and leaves earlier messages alone',()=>{
  const normalize=createEventNormalizer('s');
  normalize(event('message.part.updated',{part:part('text','earlier',{text:'Checking files.',time:{end:1}})}));
  normalize(event('message.part.updated',{part:part('text','final',{text:'Fixed',time:{start:1}})}));
  const result={info:{id:'m'},parts:[part('text','final',{text:'Fixed collisions.'})]};
  assert.deepEqual(normalize.reconcile(result),[
    {type:'delta',kind:'assistant',text:' collisions.'},
    {type:'assistant_text',text:' collisions.'},
  ]);
  assert.deepEqual(normalize.reconcile(result),[]);
});

test('a divergent final snapshot requests a canonical transcript refresh rather than appending incorrect text',()=>{
  const normalize=createEventNormalizer('s');
  normalize(event('message.part.updated',{part:part('text','final',{text:'Incorrect draft.',time:{start:1}})}));
  const result={info:{id:'m'},parts:[part('text','final',{text:'Correct answer.'})]};
  assert.deepEqual(normalize.reconcile(result),[{type:'transcript_reconcile'}]);
  assert.deepEqual(normalize.reconcile(result),[]);
});

test('ACP text, thinking and tool updates reach the player without repeating activity',()=>{
  const normalize=createAcpNormalizer('OpenCode');
  assert.deepEqual(normalize({sessionUpdate:'agent_message_chunk',messageId:'m',content:{type:'text',text:'Hello'}}),[{type:'delta',kind:'assistant',text:'Hello'},{type:'assistant_text',text:'Hello'}]);
  assert.deepEqual(normalize({sessionUpdate:'agent_thought_chunk',content:{type:'text',text:'Thinking'}}),[{type:'delta',kind:'thinking',text:'Thinking'}]);
  const call={sessionUpdate:'tool_call',toolCallId:'call_1',name:'gamesmith_reload_game',title:'gamesmith_reload_game',status:'pending',rawInput:{}};
  const started=normalize(call);
  assert.deepEqual(started[0],{type:'tool',name:'gamesmith_reload_game',description:'gamesmith_reload_game'});
  assert.equal(started[1].type,'status');
  assert.deepEqual(normalize(call),[]);
  const finished=normalize({sessionUpdate:'tool_call_update',toolCallId:'call_1',status:'completed'});
  assert.deepEqual(finished[0],{type:'tool',name:'gamesmith_reload_game',description:'completed'});
  assert.equal(finished[1].type,'status');
  assert.deepEqual(normalize({sessionUpdate:'available_commands_update',availableCommands:[]}),[]);
});

test('ACP usage reports the live context size once per change',()=>{
  const normalize=createAcpNormalizer('OpenCode');
  assert.deepEqual(normalize({sessionUpdate:'usage_update',used:5120,size:200000}),[{type:'context',tokens:5120}]);
  assert.deepEqual(normalize({sessionUpdate:'usage_update',used:5120,size:200000}),[]);
  assert.deepEqual(normalize({sessionUpdate:'usage_update',used:6400,size:200000}),[{type:'context',tokens:6400}]);
});
