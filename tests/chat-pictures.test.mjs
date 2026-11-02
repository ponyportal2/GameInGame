import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';

const directory=mkdtempSync(join(tmpdir(),'gs-chat-pictures-'));
assembleHarnessRuntime('opencode',directory);
const {hostTools,executeHostTool,toolContent}=await import(pathToFileURL(join(directory,'host-tools.mjs')));

test('picture access exposes only an opaque attachment identity',()=>{
  assert.deepEqual(Object.keys(hostTools.inspect_attachment.properties),['id']);
  assert.deepEqual(hostTools.inspect_attachment.required,['id']);
  assert(new RegExp(hostTools.inspect_attachment.properties.id.pattern).test('a'.repeat(32)));
  assert(!new RegExp(hostTools.inspect_attachment.properties.id.pattern).test('../other.png'));
});

test('attached PNG bytes reach the image tool response unchanged, outside the textual cap',async()=>{
  const png=Buffer.alloc(80*1024,7).toString('base64');
  const id='c'.repeat(32);
  let calls=0;
  const result=await executeHostTool('inspect_attachment',{id},{callHost:async(command,args)=>{
    calls++;
    assert.equal(command,'inspect_attachment');assert.deepEqual(args,{id});
    return {ok:true,id,mime_type:'image/png',image_base64:png};
  }});
  assert.equal(calls,1);
  assert(!result.output_truncated);
  const content=toolContent(result);
  assert.deepEqual(JSON.parse(content[0].text),{ok:true,id});
  assert.deepEqual(content[1],{type:'image',data:png,mimeType:'image/png'});
});
