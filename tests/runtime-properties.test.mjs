import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, mkdirSync, writeFileSync} from 'node:fs';
import {spawnSync, spawn} from 'node:child_process';
import {once} from 'node:events';
import {createInterface} from 'node:readline';
import {readdirSync, renameSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from '../tools/testing/assembled-runtime.mjs';

const inventory=JSON.parse(readFileSync('tools/agent/harnesses.json','utf8')).harnesses;
for(const harness of inventory) test(`${harness.id}: assembled runtime exposes live inspection and mutation`,async()=>{
  const directory=mkdtempSync(join(tmpdir(),'gs-runtime-tools-'));
  assembleHarnessRuntime(harness.id,directory);
  if(harness.id==='pi'){
    process.env.GAMESMITH_MODEL_PROVIDER='openai_subscription';
    const ai=join(directory,'node_modules/@earendil-works/pi-ai');mkdirSync(ai,{recursive:true});
    writeFileSync(join(ai,'package.json'),JSON.stringify({type:'module',exports:'./index.mjs'}));
    writeFileSync(join(ai,'index.mjs'),'export const Type=new Proxy({}, {get:(_,key)=>key===\'Unsafe\'?schema=>schema:()=>({})});');
    const registered=[];
    await (await import(pathToFileURL(join(directory,'gamesmith-extension.ts')))).default({on(){},registerTool(tool){registered.push(tool);}});
    for(const name of ['inspect_runtime','set_properties']) assert(registered.some(t=>t.name===name),name);
    assert.equal(registered.find(t=>t.name==='inspect_runtime').parameters.properties.offset.maximum,1000);
  }else if(harness.id==='command-code'){
    const registered=[];
    process.env.GAMESMITH_PROMPT_PATH=join(directory,'prompt.md');writeFileSync(process.env.GAMESMITH_PROMPT_PATH,'fixture');
    const mod=await import(pathToFileURL(join(directory,'gamesmith.ts')));
    await mod.default({cwd:directory,addTool(t){registered.push(t);},getAllTools(){return registered.map(t=>t.schema.name);},setActiveTools(names){
      for(const name of ['inspect_runtime','set_properties']) assert(names.includes(name),`active ${name}`);
    },hooks(){}});
    for(const name of ['inspect_runtime','set_properties']) assert(registered.some(t=>t.schema.name===name),name);
    assert.equal(registered.find(t=>t.schema.name==='inspect_runtime').schema.input_schema.properties.discover_properties.type,'boolean');
  }else{
    const {hostTools}=await import(pathToFileURL(join(directory,'host-tools.mjs')));
    for(const name of ['inspect_runtime','set_properties']){
      assert(hostTools[name],name);
      assert(hostTools[name].description.length>30);
      if(name==='inspect_runtime'){
        assert.equal(hostTools[name].properties.offset.maximum,1000);
        assert.equal(hostTools[name].properties.discover_properties.type,'boolean');
      }
      if(name==='set_properties'){
        assert.equal(hostTools[name].properties.targets.maxItems,100);
        assert(hostTools[name].properties.targets.items.properties.instance_id);
      }
    }
    const workspace=harness.modules.find(([destination])=>destination==='workspace-tools.mjs');
    if(workspace){
      const {toolSpecs}=await import(pathToFileURL(join(directory,'workspace-tools.mjs')));
      for(const name of ['inspect_runtime','set_properties']) assert(toolSpecs().some(t=>t.name==='gamesmith_'+name));
    }
  }
});

test('assembled OpenCode MCP delivers real 64-wall inspection below 24KB without spilling output', async()=>{
  const directory=mkdtempSync(join(tmpdir(),'gs-wall-mcp-'));
  assembleHarnessRuntime('opencode',directory);
  const responsePath=join(directory,'wall-response.json');
  const godot=process.env.GODOT_BIN || 'GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe';
  const fixture=spawnSync(godot,['--headless','--path','.', '--script','res://tests/runtime_wall_response.gd','--',responsePath],{
    encoding:'utf8',windowsHide:true,timeout:30000,env:{...process.env,APPDATA:directory,XDG_DATA_HOME:directory},
  });
  assert.equal(fixture.status,0,fixture.stdout+fixture.stderr);
  const response=JSON.parse(readFileSync(responsePath,'utf8'));
  assert.equal(response.nodes.length,64);
  const child=spawn(process.execPath,[join(directory,'mcp.mjs')],{env:{...process.env,GAMESMITH_HOST_BRIDGE_DIR:directory},stdio:['pipe','pipe','pipe'],windowsHide:true});
  const lines=createInterface({input:child.stdout});
  const records=[];lines.on('line',line=>records.push(JSON.parse(line)));
  const wait=async predicate=>{
    const end=Date.now()+10000;
    while(!predicate()) {assert(Date.now()<end,'MCP fixture deadline');await new Promise(resolve=>setTimeout(resolve,10));}
  };
  try {
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'inspect_runtime',arguments:{class:'Polygon2D',depth:2,properties:['color']}}})+'\n');
    let request;
    await wait(()=>request=readdirSync(directory).find(name=>/^request-.*\.json$/.test(name)));
    const input=JSON.parse(readFileSync(join(directory,request),'utf8'));
    assert.equal(input.command,'inspect_runtime');
    const output=join(directory,request.replace('request-','response-'));
    writeFileSync(output+'.tmp',JSON.stringify(response));renameSync(output+'.tmp',output);
    await wait(()=>records.some(record=>record.id===1));
    const actual=records.find(record=>record.id===1);
    assert(Buffer.byteLength(JSON.stringify(actual))<24000);
    const payload=JSON.parse(actual.result.content[0].text);
    assert.deepEqual(payload,response);
    assert(payload.nodes.every(node=>!('available_properties' in node)));
    const exited=once(child,'close');child.stdin.end();await exited;
  } finally {child.kill();lines.close();}
});
