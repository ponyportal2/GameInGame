import {readdir,lstat,readFile,realpath,mkdir,writeFile,rename,unlink,stat} from 'node:fs/promises';
import {resolve,join,relative,dirname,isAbsolute} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {workspacePath} from './workspace-paths.mjs';

export const MAX_IMAGE_BYTES=32*1024*1024;
export function imageFormat(bytes){
  if(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))return 'png';
  if(bytes[0]===255 && bytes[1]===216 && bytes[2]===255)return 'jpeg';
  if(bytes.toString('ascii',0,4)==='RIFF' && bytes.toString('ascii',8,12)==='WEBP')return 'webp';
  throw new Error('Expected a PNG, JPEG or WebP image.');
}
export async function imageBytes(path){
  const info=await stat(path);
  if(!info.isFile() || info.size>MAX_IMAGE_BYTES || !info.size)throw new Error('Image is empty, too large or not a regular file.');
  const bytes=await readFile(path);imageFormat(bytes);return bytes;
}
export function within(root,path){const r=relative(root,path);return r!== '..' && !r.startsWith('../') && !r.startsWith('..\\') && !isAbsolute(r);}
export async function snapshot(root){
  const files={};let count=0;
  async function walk(dir){for(const item of (await readdir(dir,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))){
    if(dir===root && ['.git','.godot'].includes(item.name))continue;
    if(++count>50000)throw new Error('Workspace is too large for image-job change verification.');
    const path=join(dir,item.name),s=await lstat(path),key=relative(root,path);
    if(s.isSymbolicLink()){files[key]='link:'+await realpath(path);continue;}
    if(s.isDirectory())await walk(path);
    else if(s.isFile())files[key]=createHash('sha256').update(await readFile(path)).digest('hex');
  }}
  await walk(root);return JSON.stringify(files);
}
export async function prepareJob(config){
  const root=await realpath(config.workspace),target=config.target_path;
  if(typeof target!=='string' || !target.toLowerCase().endsWith('.png'))throw new Error('target_path must be a relative .png path.');
  if(target.replaceAll('\\','/').split('/').some(p=>p==='..' || p.toLowerCase()==='.godot'))throw new Error('Reserved or escaping output path.');
  await workspacePath(root,target,{destructive:true});
  const references=config.reference_paths || [];
  if(!Array.isArray(references) || references.length>4)throw new Error('At most four reference images are supported.');
  const baseline=await snapshot(root),refs=[];
  for(const [i,value]of references.entries()){
    const bytes=await imageBytes(await workspacePath(root,value));
    const path=join(config.directory,'references',`${i}.${imageFormat(bytes)}`);
    await mkdir(dirname(path),{recursive:true});await writeFile(path,bytes);refs.push(path);
  }
  return {root,refs,async publish(){
    if(await realpath(config.workspace)!==root || await snapshot(root)!==baseline)throw new Error('Workspace changed during image generation. Result was not published; retry when edits have finished.');
    let path=await workspacePath(root,target,{destructive:true});
    await mkdir(dirname(path),{recursive:true});
    path=await workspacePath(root,target,{destructive:true});
    const bytes=await imageBytes(join(config.directory,'result.png'));
    if(imageFormat(bytes)!=='png')throw new Error('Host did not produce a validated PNG.');
    const temporary=join(dirname(path),'.gamesmith-image-'+randomUUID()+'.tmp');
    try{
      await writeFile(temporary,bytes,{flag:'wx'});
      await workspacePath(root,target,{destructive:true});
      await rename(temporary,path);return target.replaceAll('\\','/');
    }finally{await unlink(temporary).catch(()=>{});}
  }};
}
