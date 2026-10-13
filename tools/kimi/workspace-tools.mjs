import { readFile, writeFile, mkdir, readdir, stat, rename, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { workspacePath } from './workspace-paths.mjs';
import { hostTools } from './host-tools.mjs';

const fileTools={
  read:{description:'Read a workspace text file in bounded pages (1-based line offset).',properties:{path:{type:'string'},offset:{type:'integer'},limit:{type:'integer'}},required:['path']},
  write:{description:'Write a new file or deliberately replace a workspace file. Inspect existing files first.',properties:{path:{type:'string'},content:{type:'string'}},required:['path','content']},
  edit:{description:'Replace one unique exact text match in a workspace file; ambiguous matches fail without changes.',properties:{path:{type:'string'},old_text:{type:'string'},new_text:{type:'string'}},required:['path','old_text','new_text']},
  list:{description:'List one workspace directory, bounded to 500 entries.',properties:{path:{type:'string'}},required:[]},
  search:{description:'Search literal text in workspace text files, excluding .git and .godot. Bounded results; narrow path as needed.',properties:{path:{type:'string'},pattern:{type:'string'}},required:['pattern']},
};
export function toolSpecs() {
  return Object.entries({...fileTools,...hostTools}).map(([name,t])=>({type:'function',name:'gamesmith_'+name,description:t.description,
    inputSchema:{type:'object',properties:t.properties,required:t.required || [],additionalProperties:false}}));
}
async function textFile(path) {
  if ((await stat(path)).size>2*1024*1024) throw new Error('File exceeds the 2 MB text-tool limit.');
  const data=await readFile(path);if (data.includes(0)) throw new Error('Expected a text file.');return data.toString('utf8');
}
async function callHost(config,command,args,signal) {
  const id=randomUUID(),request=join(config.bridge_dir,`request-${id}.json`),response=join(config.bridge_dir,`response-${id}.json`);
  signal?.throwIfAborted();
  await writeFile(request+'.tmp',JSON.stringify({id,command,args}));await rename(request+'.tmp',request);
  try {
    for (;;) {
      signal?.throwIfAborted();
      try {const result=JSON.parse(await readFile(response,'utf8'));await rm(response);return result;}
      catch(error) {if(error.code!=='ENOENT') throw error;}
      await new Promise(resolve=>setTimeout(resolve,25));
    }
  } finally {await rm(request,{force:true});await rm(response,{force:true});}
}
export async function executeTool(config,tool,args={},signal) {
  signal?.throwIfAborted();
  const name=tool.startsWith('gamesmith_') ? tool.slice(10) : '';
  if (Object.hasOwn(hostTools,name)) return callHost(config,name,args,signal);
  if (!Object.hasOwn(fileTools,name)) throw new Error('Unknown GameSmith tool: '+tool);
  const path=await workspacePath(config.workspace,args.path || '.',{destructive:name==='write' || name==='edit'});
  signal?.throwIfAborted();
  if (name==='read') {
    const lines=(await textFile(path)).split('\n'),offset=Math.max(1,args.offset || 1),limit=Math.min(500,Math.max(1,args.limit || 200));
    const page=[];let size=0;
    for(const line of lines.slice(offset-1,offset-1+limit)) {
      if(line.length>32000) throw new Error('A line exceeds the 32,000-character text-page limit.');
      if(size+line.length+1>32000)break;
      page.push(line);size+=line.length+1;
    }
    const next=offset+page.length;
    return {ok:true,text:page.join('\n'),offset,total_lines:lines.length,next_offset:next,truncated:next<=lines.length};
  }
  if (name==='write' || name==='edit') {
    let text=args.content;
    if (name==='edit') {
      text=await textFile(path);
      if (typeof args.old_text!=='string' || !args.old_text) throw new Error('Expected non-empty old_text.');
      const at=text.indexOf(args.old_text);
      if (at<0) throw new Error('Exact text was not found.');
      if (text.indexOf(args.old_text,at+1)>=0) throw new Error('Exact edit is ambiguous; include more context.');
      if(typeof args.new_text!=='string') throw new Error('Expected new_text.');
      text=text.slice(0,at)+args.new_text+text.slice(at+args.old_text.length);
    }
    if(typeof text!=='string' || Buffer.byteLength(text)>2*1024*1024) throw new Error('Expected text of at most 2 MB.');
    signal?.throwIfAborted();await mkdir(dirname(path),{recursive:true});signal?.throwIfAborted();await writeFile(path,text);return {ok:true,path:args.path};
  }
  if (name==='list') {
    const entries=await readdir(path,{withFileTypes:true});
    return {ok:true,entries:entries.slice(0,500).map(e=>e.name+(e.isDirectory()?'/':'')),truncated:entries.length>500};
  }
  if(typeof args.pattern!=='string' || !args.pattern) throw new Error('Expected a non-empty literal pattern.');
  const matches=[];let visited=0,truncated=false;
  async function search(target,relative) {
    signal?.throwIfAborted();
    if(++visited>2000 || matches.length>=100) {truncated=true;return;}
    if ((await stat(target)).isDirectory()) {
      for (const entry of await readdir(target,{withFileTypes:true})) {
        if (['.git','.godot'].includes(entry.name) || entry.isSymbolicLink()) continue;
        if(visited>=2000 || matches.length>=100) {truncated=true;break;}
        const rel=relative==='.' ? entry.name : relative+'/'+entry.name;
        const safe=await workspacePath(config.workspace,rel);await search(safe,rel);
      }
    } else {
      let text;try {text=await textFile(target);} catch {return;}
      for (const [index,line] of text.split('\n').entries()) if(line.includes(args.pattern)) {
        matches.push({path:relative,line:index+1,text:line.slice(0,1000)});if(matches.length>=100) {truncated=true;break;}
      }
    }
  }
  await search(path,args.path || '.');return {ok:true,matches,truncated};
}
