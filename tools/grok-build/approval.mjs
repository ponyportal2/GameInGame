import {isDeepStrictEqual} from 'node:util';
import {writeFile,rename,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';

// ACP permission waits happen before Grok Build starts MCP execution.
// A single-use grant connects that native permission to the actual host reload.
export async function authorizeReload(config,signal) {
  const id=randomUUID(),token=randomUUID();
  const request=join(config.bridge_dir,`request-${id}.json`),response=join(config.bridge_dir,`response-${id}.json`);
  signal.throwIfAborted();await writeFile(request+'.tmp',JSON.stringify({id,command:'authorize_reload',args:{token}}));await rename(request+'.tmp',request);
  try {
    for(;;){
      signal.throwIfAborted();let result;
      try{result=JSON.parse(await readFile(response,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
      if(result){if(!result.ok)throw new Error(result.error || 'Reload approval was cancelled.');signal.throwIfAborted();
        await writeFile(join(config.bridge_dir,'reload-grant.json'),JSON.stringify({token}));return;}
      await new Promise(resolve=>setTimeout(resolve,25));
    }
  }finally{await rm(request,{force:true});await rm(response,{force:true});}
}
export async function consumeReloadGrant(config) {
  const path=join(config.bridge_dir,'reload-grant.json');
  try{const data=JSON.parse(await readFile(path,'utf8'));await rm(path);return data.token;}
  catch(error){if(error.code==='ENOENT')throw new Error('Reload has no active ACP approval.');throw error;}
}

// Wait at ACP permission time, before the native MCP execution deadline starts.
export async function authorizeBlender(config,args,signal) {
  const id=randomUUID(),token=randomUUID();
  const request=join(config.bridge_dir,`request-${id}.json`),response=join(config.bridge_dir,`response-${id}.json`);
  signal.throwIfAborted();
  await writeFile(request+'.tmp',JSON.stringify({id,command:'authorize_blender',args:{token,blender_args:args}}));
  await rename(request+'.tmp',request);
  try {
    for(;;){
      signal.throwIfAborted();let result;
      try{result=JSON.parse(await readFile(response,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
      if(result){
        if(!result.ok)throw new Error(result.error || 'Blender approval was cancelled.');
        signal.throwIfAborted();
        await writeFile(join(config.bridge_dir,'blender-grant.json'),JSON.stringify({token,args}));return;
      }
      await new Promise(resolve=>setTimeout(resolve,25));
    }
  }finally{await rm(request,{force:true});await rm(response,{force:true});}
}
export async function consumeBlenderGrant(config,args) {
  const path=join(config.bridge_dir,'blender-grant.json'),claimed=path+'.'+randomUUID();
  try {
    await rename(path,claimed);
    const data=JSON.parse(await readFile(claimed,'utf8'));
    if(!data.token || !isDeepStrictEqual(data.args,args))throw new Error('Blender approval does not match the requested arguments.');
    return data.token;
  }catch(error){if(error.code==='ENOENT')throw new Error('Blender script has no active ACP approval.');throw error;}
  finally{await rm(claimed,{force:true});}
}
