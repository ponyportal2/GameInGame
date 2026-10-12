import {writeFile,rename,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';

// ACP permission waits happen before Cline starts its finite MCP deadline.
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
