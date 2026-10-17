import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, mkdirSync, writeFileSync} from 'node:fs';
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
  }else if(harness.id==='command-code'){
    const registered=[];
    process.env.GAMESMITH_PROMPT_PATH=join(directory,'prompt.md');writeFileSync(process.env.GAMESMITH_PROMPT_PATH,'fixture');
    const mod=await import(pathToFileURL(join(directory,'gamesmith.ts')));
    await mod.default({cwd:directory,addTool(t){registered.push(t);},getAllTools(){return registered.map(t=>t.schema.name);},setActiveTools(names){
      for(const name of ['inspect_runtime','set_properties']) assert(names.includes(name),`active ${name}`);
    },hooks(){}});
    for(const name of ['inspect_runtime','set_properties']) assert(registered.some(t=>t.schema.name===name),name);
  }else{
    const {hostTools}=await import(pathToFileURL(join(directory,'host-tools.mjs')));
    for(const name of ['inspect_runtime','set_properties']){
      assert(hostTools[name],name);
      assert(hostTools[name].description.length>30);
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
