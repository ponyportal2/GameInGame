import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,mkdirSync,symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';
const dir=mkdtempSync(join(tmpdir(),'gs-output-'));
assembleHarnessRuntime('opencode',dir);
const mod=await import(pathToFileURL(join(dir,'host-tools.mjs')));
for(const [label,result] of [
 ['bytes',{ok:true,text:'\u{1f4a1}'.repeat(30000)}],
 ['lines',{ok:true,text:'x\n'.repeat(2500)}],
 ['error',{ok:false,error:'bad '.repeat(30000)}],
 ['mutation',{ok:true,changed:100,failed:0,temporary:true,results:[{text:'x'.repeat(100000)}]}],
]) test('bounded '+label,()=>{
 assert.equal(typeof mod.boundedToolResult,'function');
 const bounded=mod.boundedToolResult(result);
 const text=mod.toolContent(bounded)[0].text;
 assert(Buffer.byteLength(text)<=51200);
 assert(text.split('\n').length<=2000);
 assert(bounded.output_truncated);
 assert.equal(bounded.ok,result.ok);
 if(label==='mutation') {assert.equal(bounded.changed,100);assert.equal(bounded.temporary,true);}
 assert.deepEqual(JSON.parse(text),bounded);
});
test('small results and image payloads survive',()=>{
 const result={ok:true,nodes:[]};assert.deepEqual(mod.boundedToolResult(result),result);
 const blocks=mod.toolContent({...result,image_base64:'x'.repeat(100000),mime_type:'image/png'});
 assert.equal(blocks[1].data.length,100000);
});
test('system rg finds source locations without shell interpretation',async()=>{
 writeFileSync(join(dir,'main.gd'),'var light_energy = 0.5\nvar other = 1\n');
 mkdirSync(join(dir,'.git'));writeFileSync(join(dir,'.git','private'),'light_energy');
 const result=await mod.executeHostTool('rg_search',{target:'source',pattern:'light_energy',glob:'*.gd'},{workspace:dir});
 assert(result.ok);assert(result.matches.some(m=>m.path==='main.gd' && m.line===1));
 assert(!result.matches.some(m=>m.path.includes('.git')));
 await assert.rejects(()=>mod.executeHostTool('rg_search',{target:'source',pattern:'x',path:'../'},{workspace:dir}),/workspace|escape/i);
});
test('runtime rg returns complete observed handles and continuation',async()=>{
 const nodes=[{handle:{path:'Fill',instance_id:'1',game_generation:'9'},class:'DirectionalLight3D',values:{light_energy:0.55}}, {handle:{path:'Sun',instance_id:'2',game_generation:'9'},class:'DirectionalLight3D',values:{light_energy:2.2}}];
 const calls=[];
 const result=await mod.executeHostTool('rg_search',{target:'runtime',pattern:'Fill',properties:['light_energy']},{workspace:dir,callHost:async(name,args)=>{calls.push([name,args]);return {ok:true,nodes,has_more:true,next_offset:100,game_generation:'9',truncated_by:['result_limit']};}});
 assert(result.ok);assert.deepEqual(result.nodes,[nodes[0]]);assert.equal(result.runtime_next_offset,100);
 assert.equal(calls[0][0],'inspect_runtime');assert.equal(calls[0][1].discover_properties,false);
});
test('rg cancellation and invalid regex are concrete errors',async()=>{
 const result=await mod.executeHostTool('rg_search',{target:'source',pattern:'['},{workspace:dir});assert.equal(result.ok,false);
 const abort=new AbortController();abort.abort();
 await assert.rejects(()=>mod.executeHostTool('rg_search',{target:'source',pattern:'x'},{workspace:dir,signal:abort.signal}),/abort/i);
});


test('rg match pagination has no false final continuation',async()=>{
 writeFileSync(join(dir,'pages.gd'),'marker one\nmarker two\nmarker three\n');
 const call=offset=>mod.executeHostTool('rg_search',{target:'source',pattern:'marker',path:'pages.gd',limit:2,offset},{workspace:dir});
 const first=await call(0);assert.equal(first.next_offset,2);assert.equal(first.matches.length,2);
 const last=await call(first.next_offset);assert.equal(last.has_more,false);assert.equal(last.next_offset,null);assert.equal(last.matches[0].line,3);
 const empty=await call(10);assert.deepEqual(empty.matches,[]);assert.equal(empty.has_more,false);
});
test('rg refuses junction escapes and never follows nested junctions',async()=>{
 const outside=mkdtempSync(join(tmpdir(),'gs-outside-'));
 writeFileSync(join(outside,'secret.gd'),'outside_secret');
 symlinkSync(outside,join(dir,'escape'),'junction');
 await assert.rejects(()=>mod.executeHostTool('rg_search',{target:'source',pattern:'outside_secret',path:'escape'},{workspace:dir}),/workspace|escape/i);
 const result=await mod.executeHostTool('rg_search',{target:'source',pattern:'outside_secret',glob:'*.gd'},{workspace:dir});
 assert(result.ok);assert.deepEqual(result.matches,[]);
});
test('runtime search propagates inspection failures and paginates complete records',async()=>{
 const failure={ok:false,error:'No active game'};
 const rejected=await mod.executeHostTool('rg_search',{target:'runtime',pattern:'x'},{workspace:dir,callHost:async()=>failure});
 assert.deepEqual(rejected,failure);
 const nodes=Array.from({length:3},(_,i)=>({handle:{path:'Light'+i,instance_id:String(i+1),game_generation:'9'},class:'DirectionalLight3D'}));
 const callHost=async()=>({ok:true,nodes,next_offset:null,truncated_by:[],game_generation:'9'});
 const first=await mod.executeHostTool('rg_search',{target:'runtime',pattern:'Light',limit:2},{workspace:dir,callHost});
 const last=await mod.executeHostTool('rg_search',{target:'runtime',pattern:'Light',limit:2,offset:first.next_offset},{workspace:dir,callHost});
 assert.deepEqual([...first.nodes,...last.nodes],nodes);assert.equal(last.has_more,false);
});
test('byte boundary is inclusive and truncation remains valid UTF-8',()=>{
 const base=Buffer.byteLength(JSON.stringify({ok:true,text:''}));
 const exact={ok:true,text:'a'.repeat(51200-base)};
 assert.equal(mod.boundedToolResult(exact),exact);
 const over=mod.boundedToolResult({...exact,text:exact.text+'a'});
 assert.deepEqual(over.truncated_by,['byte_limit']);
 const unicode=mod.toolContent({ok:true,text:'\u{1f4a1}'.repeat(30000)})[0].text;
 assert.equal(Buffer.from(unicode).toString('utf8'),unicode);assert(!unicode.includes('\ufffd'));
});

test('missing system rg fails explicitly',async()=>{
 const saved=process.env.PATH;
 try {
  process.env.PATH=dir;
  const result=await mod.executeHostTool('rg_search',{target:'source',pattern:'marker',path:'pages.gd'},{workspace:dir});
  assert.equal(result.ok,false);assert.match(result.error,/rg.*PATH|rg.*installed/);
 } finally {process.env.PATH=saved;}
});

test('source match pages follow sorted file paths',async()=>{
 const folder=join(dir,'ordered');mkdirSync(folder);
 for(const name of ['z.gd','b.gd','a.gd'])writeFileSync(join(folder,name),'ordered_marker');
 const paths=[];
 for(let offset=0;offset<3;offset++){
  const result=await mod.executeHostTool('rg_search',{target:'source',pattern:'ordered_marker',path:'ordered',offset,limit:1},{workspace:dir});
  assert(result.ok);paths.push(result.matches[0].path);
 }
 assert.deepEqual(paths,['ordered/a.gd','ordered/b.gd','ordered/z.gd']);
});
