import * as Native from './server.mjs';
import {writeFile,mkdir,realpath,readdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {within,imageBytes,snapshot} from './image-job.mjs';

// Separate native conversations; no coding session identity or workspace is passed in.
export function createBackend(config){
  let server;
  const cfg={...config,image_job:true,session_file:join(config.directory,'session.json'),prompt_path:join(config.directory,'instructions.md'),config_path:join(config.directory,'job.json')};
  const instructions='Generate exactly one image using your native image generator. Do not use shell, code, browser, MCP, file editing or other tools. Do not inspect project files. Do not install anything.';
  async function initialize(){await mkdir(join(config.directory,'native-workspace'),{recursive:true});await writeFile(cfg.prompt_path,instructions);}
  function prompt(refs){return `${instructions}\n${config.harness==='agy'?'Prefer the built-in image-generator subagent.':''}\nImage: ${config.prompt}\nPurpose: ${config.purpose || 'game asset'}\n${config.transparent?'The background must be transparent.':''}\nSave the image to ${join(config.directory,'native-workspace','output.png')}.\n${refs.length?'Reference images: '+refs.join(', '):''}`;}
  async function guard(operation){
    const cwd=join(config.directory,'native-workspace'),before=JSON.parse(await snapshot(cwd));
    const result=await operation(),after=JSON.parse(await snapshot(cwd));
    for(const path of new Set([...Object.keys(before),...Object.keys(after)])){
      const normalized=path.replaceAll('\\','/');
      if(before[path]===after[path] || normalized==='output.png' || config.harness==='codex' && /^\.codex\/generated_images\/[^/]+\/[^/]+\.png$/.test(normalized))continue;
      throw new Error('Native image worker changed an unexpected file: '+normalized);
    }
    return result;
  }
  async function safeArtifact(value,session,conversations=[]){
    const roots=[await realpath(join(config.directory,'native-workspace'))];
    if(config.harness==='grok-build' && /^[a-zA-Z0-9_-]+$/.test(session || ''))roots.push(join(homedir(),'.grok','sessions',encodeURIComponent(server.cwd),session,'images'));
    const agyRoots=config.harness==='agy'?conversations.map(id=>join(homedir(),'.gemini','antigravity','brain',id)):[];
    roots.push(...agyRoots);
    const candidates=[];
    function collect(v){
      if(typeof v==='string'){
        if(/\.(png|jpe?g|webp)$/i.test(v))candidates.push(v);
        // Some native tools serialize their structured result into a string.
        else if(v.startsWith('{') || v.startsWith('['))try{collect(JSON.parse(v))}catch{}
      }else if(Array.isArray(v))v.forEach(collect);
      else if(v && typeof v==='object')Object.values(v).forEach(collect);
    }
    collect(value);
    async function selected(paths){
      for(const candidate of paths){
        let path;try{path=await realpath(resolve(server.cwd || config.directory,candidate));}catch{continue;}
        if(!roots.some(root=>within(root,path)))throw new Error('Native image artifact escaped its allowed output locations.');
        try{await imageBytes(path);return {path};}catch{}
      }
    }
    const explicit=await selected(candidates);if(explicit)return explicit;
    // AGY's native generator stores artifacts in conversation-specific brain
    // directories. Only inspect fresh IDs emitted by this worker, never other
    // conversations, their transcripts, or paths inferred from terminal prose.
    const generated=[];
    for(const root of agyRoots){
      const entries=await readdir(root,{withFileTypes:true}).catch(error=>{if(error.code==='ENOENT')return [];throw error;});
      if(entries.length>1000)throw new Error('AGY image artifact directory is unexpectedly large.');
      generated.push(...entries.filter(entry=>entry.isFile() && /\.(png|jpe?g|webp)$/i.test(entry.name)).map(entry=>join(root,entry.name)));
    }
    if(generated.length>1)throw new Error('AGY returned multiple image artifacts without selecting one. Request exactly one image.');
    const discovered=await selected(generated);if(discovered)return discovered;
    throw new Error('Native image tool did not return an accessible, supported image artifact.');
  }
  async function codex(refs,probe){
    let complete,fail,item;
    const finished=new Promise((resolve,reject)=>{complete=resolve;fail=reject;});finished.catch(()=>{});
    server=new Native.CodexServer({workspace:join(config.directory,'native-workspace'),onExit:fail,onEvent:(method,p)=>{
      if(method==='item/completed' && p.item?.type==='imageGeneration')item=p.item;
      if(method==='turn/completed')complete(p.turn);
    }});
    await server.start();
    const caps=await server.request('modelProvider/capabilities/read'),account=await server.request('account/read');
    if(!caps.imageGeneration)throw new Error('This Codex runtime/provider does not advertise native image generation.');
    if(account.account?.type!=='chatgpt')throw new Error('Sign into Codex with a ChatGPT subscription to use native image generation.');
    if(probe)return {available:true,reason:'ChatGPT sign-in and native image capability detected; account limits are checked when generating.'};
    const current=await server.request('config/read',{includeLayers:false});
    const mcp_servers=Object.fromEntries(Object.keys(current.config?.mcp_servers || {}).map(name=>[name,{enabled:false}]));
    const thread=await server.request('thread/start',{cwd:join(config.directory,'native-workspace'),ephemeral:true,approvalPolicy:'never',sandbox:'read-only',baseInstructions:instructions,config:{mcp_servers,web_search:'disabled',features:{shell_tool:false,multi_agent:false,apps:false,plugins:false,view_image:false,browser_use:false,browser_use_external:false,computer_use:false,code_mode:false}}});
    const input=[{type:'text',text:prompt(refs),text_elements:[]},...refs.map(path=>({type:'localImage',path}))];
    // Production uses the account's native defaults. Test launcher selects Luna/xhigh.
    const turn=await guard(async()=>{
      await server.request('turn/start',{threadId:thread.thread.id,input,...(process.env.GAMESMITH_CODEX_BIN?.endsWith('codex-luna-launcher.mjs')?{model:'gpt-6-luna',effort:'xhigh'}:{})});
      return finished;
    });
    if(turn.status!=='completed' || item?.status!=='completed' || !item.result)throw new Error(turn.error?.message || item?.failure?.type || 'Codex did not complete native image generation.');
    return {bytes:Buffer.from(item.result,'base64')};
  }
  async function agy(refs,probe){
    let ready,complete,fail,artifact;
    const conversations=new Set();
    const remember=id=>{if(typeof id==='string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(id) && conversations.size<16)conversations.add(id);};
    const initialized=new Promise((resolve,reject)=>{ready=resolve;fail=reject;});
    const finished=new Promise((resolve,reject)=>{complete=resolve;const old=fail;fail=e=>{old(e);reject(e)}});finished.catch(()=>{});
    server=new Native.AgyServer(cfg,{onExit:fail,onRecord:r=>{
      remember(r.init?.conversation_id);remember(r.step_update?.conversation_id);remember(r.result?.conversation_id);
      for(const child of r.step_update?.subagent_info?.subagents || [])if(child.type_name==='image-generator')remember(child.conversation_id);
      if(r.event==='init')ready(r.init);
      if(r.event==='step_update' && r.step_update?.step_type==='tool' && r.step_update.state==='DONE'){
        const step=r.step_update;
        if(['generate_image','invoke_subagent'].includes(step.tool_name || step.tool_info?.name))artifact=step.tool_info?.output || step.output;
      }
      if(r.event==='result')complete(r.result || r);
    }});
    await server.start();const init=await initialized;
    if(!init.tools?.includes('generate_image'))throw new Error('This AGY runtime does not advertise native image generation.');
    if(probe)return {available:true,reason:'Native image tool detected; authentication, location and quota are checked when generating.'};
    const result=await guard(async()=>{server.prompt(prompt(refs));return finished;});
    if(result.status==='ERROR' || result.status==='error')throw new Error(result.error || result.error_message || result.text || 'AGY image generation failed; check account/location availability.');
    return safeArtifact(artifact,undefined,[...conversations]);
  }
  async function grok(refs,probe){
    let artifact,error,session;const calls=new Map();
    server=new Native.GrokBuildServer(cfg,{onEvent:(method,p)=>{
      const u=p.update;if(method!=='session/update' || !u)return;
      const name=u._meta?.['x.ai/tool']?.name;
      if(name && ['image_gen','image_edit'].includes(name))calls.set(u.toolCallId,name);
      if(calls.has(u.toolCallId) && u.status==='completed')artifact=u.rawOutput || u.content;
      if(calls.has(u.toolCallId) && u.status==='failed')error=u.rawOutput?.message || u.content?.map(c=>c.content?.text || '').filter(Boolean).join('\n') || 'Grok native image tool failed.';
    },onRequest:async(method,p)=>{
      if(method!=='session/request_permission')throw new Error('Image jobs do not support filesystem, terminal or other client requests.');
      const name=p.toolCall?._meta?.['x.ai/tool']?.name;
      const allowed=calls.has(p.toolCall?.toolCallId) && ['image_gen','image_edit'].includes(name);
      const option=p.options?.find(o=>o.kind===(allowed?'allow_once':'reject_once'));
      return {outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}};
    }});
    await server.start();const result=await server.request('session/new',server.sessionParams());session=result.sessionId;
    if(probe)return {available:true,reason:'Grok Build authenticated; image subscription/credits are checked when generating.'};
    await guard(()=>server.request('session/prompt',{sessionId:session,prompt:[{type:'text',text:prompt(refs)+(refs.length?' Use image_edit with these image paths.':' Use image_gen (the native /imagine tool).')}]}));
    if(error)throw new Error(error);return safeArtifact(artifact,session);
  }
  async function run(refs,probe){
    await initialize();
    if(config.harness==='codex')return codex(refs,probe);
    if(config.harness==='agy')return agy(refs,probe);
    if(config.harness==='grok-build')return grok(refs,probe);
    if(config.harness==='cursor'){
      server=new Native.CursorServer(cfg);await server.start();
      if(probe)return {available:true,reason:'Cursor CLI authenticated; native print image generation and quota are checked when generating.'};
      const result=await guard(()=>server.generateImage(prompt(refs)));return safeArtifact(result);
    }
    throw new Error('Unsupported image backend.');
  }
  return {async probe(){try{return await run([],true)}catch(e){return {available:false,reason:e.message}}},generate:refs=>run(refs,false),close(){server?.close()}};
}
