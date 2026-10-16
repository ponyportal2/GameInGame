import {readFile,writeFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
import {join} from 'node:path';
import {prepareJob,imageBytes,imageFormat,MAX_IMAGE_BYTES} from './image-job.mjs';
import {createBackend} from './image-backend.mjs';
const config=JSON.parse(await readFile(process.argv[2],'utf8'));
const emit=record=>process.stdout.write(JSON.stringify(record)+'\n');
const backend=createBackend(config);let job,ready=false,stopped=false,phase='input';
const timer=setTimeout(()=>{stopped=true;backend.close();emit({type:'image_error',phase,error:config.probe?'Capability check timed out.':'Image job timed out after five minutes.'});process.exit(0);},config.probe?20000:300000);
createInterface({input:process.stdin}).on('line',async line=>{
  let r;try{r=JSON.parse(line);if(r.type!=='publish' || !ready || stopped)throw new Error('Image is not ready to publish.');
    const path=await job.publish();emit({type:'response',id:r.id,success:true,path});
  }catch(error){emit({type:'response',id:r?.id,success:false,error:error.message});}
});
try{
  if(config.probe){emit({type:'image_capability',...await backend.probe()});}
  else{
    if(typeof config.prompt!=='string' || !config.prompt.trim() || config.prompt.length>16000)throw new Error('A prompt of 1–16000 characters is required.');
    job=await prepareJob(config);
    phase='native';
    const result=await backend.generate(job.refs);
    phase='result';
    if(stopped)throw new Error('Image generation was cancelled.');
    const bytes=result.bytes ? Buffer.from(result.bytes) : await imageBytes(result.path);
    if(bytes.length>MAX_IMAGE_BYTES)throw new Error('Generated image exceeds 32 MB.');
    const format=imageFormat(bytes);
    await writeFile(join(config.directory,'result.raw'),bytes);
    ready=true;emit({type:'image_ready',format});
  }
}catch(error){if(!stopped)emit({type:'image_error',phase,error:String(error.message).slice(0,2000)});}
finally{clearTimeout(timer);backend.close();if(!ready)process.exit(0);}
