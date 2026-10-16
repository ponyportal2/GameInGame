import {resolve,dirname} from 'node:path';
import {realpathSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
export function permittedImageTool(input, mode, cwd){
  const name=input.tool_name,args=input.tool_input || {};
  const references=values=>{
    if(!Array.isArray(values))return false;
    return values.every(value=>{
      if(typeof value!=='string')return false;
      try{const path=realpathSync(resolve(cwd,value));return dirname(path)===realpathSync(resolve(cwd,'../references')) && /[0-3]\.(png|jpeg|webp)$/.test(path);}catch{return false;}
    });
  };
  if(mode==='grok-build')return name==='image_gen' || name==='image_edit' && references(typeof args.image==='string'?[args.image]:args.image);
  if(mode!=='cursor')return false;
  if(['GenerateImage','generate_image','generateImage'].includes(name))return references(args.reference_image_paths || args.referenceImagePaths || []) && [args.filename,args.filePath,args.file_path].every(path=>path===undefined || typeof path==='string' && resolve(cwd,path)===resolve(cwd,'output.png'));
  if(name==='Write')return typeof args.file_path==='string' && resolve(cwd,args.file_path)===resolve(cwd,'output.png');
  // Cursor may ask for its native tool schema before invoking GenerateImage.
  return name==='GetMcpTools' && args.server==='cursor' && args.toolName==='GenerateImage';
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',b=>text+=b);
  process.stdin.on('end',()=>{
    let allowed=false;try{allowed=permittedImageTool(JSON.parse(text),process.argv[2],process.argv[3]);}catch{}
    console.log(JSON.stringify(process.argv[2]==='cursor'?{permission:allowed?'allow':'deny',agent_message:'This worker may only generate the requested image.'}:{decision:allowed?'allow':'deny',reason:'This worker may only generate images.'}));
    if(!allowed)process.exitCode=2;
  });
}
