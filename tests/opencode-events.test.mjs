import test from 'node:test';
import assert from 'node:assert/strict';
import { createEventNormalizer } from '../tools/opencode/events.mjs';

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
