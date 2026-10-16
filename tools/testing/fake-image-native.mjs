import {createInterface} from 'node:readline';
import {writeFileSync,mkdirSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
const valid=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==','base64');
const bytes=process.env.GAMESMITH_IMAGE_FIXTURE==='corrupt'?valid.subarray(0,16):valid;
const emit=r=>console.log(JSON.stringify(r));
const fail=process.env.GAMESMITH_IMAGE_FIXTURE==='fail';
const mode=process.env.GAMESMITH_IMAGE_FIXTURE || '';
function waiting(){if(mode!=='wait')return false;writeFileSync(join(process.cwd(),'../native-wait.txt'),String(process.pid));return true;}
if(process.argv.includes('status')){emit({isAuthenticated:process.env.GAMESMITH_IMAGE_FIXTURE!=='logged-out'});process.exit(0);}
if(process.argv.includes('--print') && waiting())setInterval(()=>{},1000);
else if(process.argv.includes('--print')){
  if(!fail)writeFileSync('output.png',bytes);
  emit({tool_call:{generateImageToolCall:{result:fail?{error:{error:'Fixture image limit'}}:{success:{path:'output.png'}}}}});process.exit(0);
}
const agy=process.argv.includes('--agent'),grok=process.argv.includes('agent');
if(agy)emit({event:'init',init:{tools:['generate_image']}});
createInterface({input:process.stdin}).on('line',line=>{
  const r=JSON.parse(line),reply=result=>emit({id:r.id,result});
  if(r.event==='user'){
    if(waiting())return;
    if(mode.startsWith('agy-')){
      const parent='11111111-1111-4111-8111-111111111111',child='22222222-2222-4222-8222-222222222222',foreign='33333333-3333-4333-8333-333333333333';
      const root=join(homedir(),'.gemini','antigravity','brain',mode==='agy-foreign'?foreign:child);
      if(mode!=='agy-reference'){
        mkdirSync(root,{recursive:true});writeFileSync(join(root,'generated_123.png'),bytes);
        if(mode==='agy-ambiguous')writeFileSync(join(root,'generated_456.png'),bytes);
      }
      emit({event:'step_update',step_update:{conversation_id:parent,state:'DONE',step_type:'subagent',subagent_info:{subagents:[{type_name:'image-generator',conversation_id:child}]}}});
      if(['agy-foreign','agy-reference'].includes(mode))emit({event:'step_update',step_update:{state:'DONE',step_type:'tool',tool_name:'generate_image',tool_info:{output:{path:mode==='agy-reference'?join(process.cwd(),'../references/0.png'):join(root,'generated_123.png')}}}});
      emit({event:'result',result:{status:'SUCCESS',conversation_id:parent}});return;
    }
    if(!fail){writeFileSync('output.png',bytes);emit({event:'step_update',step_update:{step_type:'tool',state:'DONE',tool_name:'generate_image',tool_info:{output:{path:join(process.cwd(),'output.png')}}}});}
    emit({event:'result',result:{status:fail?'ERROR':'SUCCESS',error:fail?'Fixture image limit':undefined}});return;
  }
  if(grok){
    if(r.method==='initialize')return reply({_meta:{grokShell:true},authMethods:[{id:'cached_token'}],agentCapabilities:{loadSession:true}});
    if(r.method==='session/new')return reply({sessionId:'image-fixture'});
    if(r.method==='session/prompt'){
      if(waiting())return;
      const meta={'x.ai/tool':{name:'image_gen'}};
      emit({method:'session/update',params:{update:{sessionUpdate:'tool_call',toolCallId:'image',_meta:meta}}});
      let artifact=join(process.cwd(),'output.png');
      if(mode.startsWith('grok-')){
        const group=mode==='grok-long'?'native-workspace-a1b2c3d4':encodeURIComponent(process.cwd());
        const root=join(process.env.GROK_HOME || join(homedir(),'.grok'),'sessions',group);
        const images=join(root,mode==='grok-foreign'?'other-session':'image-fixture','images');
        mkdirSync(root,{recursive:true});
        if(mode==='grok-long')writeFileSync(join(root,'.cwd'),process.cwd());
        if(mode==='grok-link' || mode==='grok-outside'){
          const outside=mode==='grok-link'?join(root,'other-session','images'):join(process.cwd(),'../../outside-images');
          mkdirSync(outside,{recursive:true});mkdirSync(join(root,'image-fixture'),{recursive:true});
          symlinkSync(outside,images,process.platform==='win32'?'junction':'dir');
        }else mkdirSync(images,{recursive:true});
        artifact=join(images,'native.png');
      }
      if(!fail)writeFileSync(artifact,bytes);
      emit({method:'session/update',params:{update:{sessionUpdate:'tool_call_update',toolCallId:'image',status:fail?'failed':'completed',rawOutput:fail?{message:'Fixture image limit'}:{path:artifact}}}});return reply({stopReason:'end_turn'});
    }
    return reply({});
  }
  if(r.method==='modelProvider/capabilities/read')return reply({imageGeneration:process.env.GAMESMITH_IMAGE_FIXTURE!=='no-capability'});
  if(r.method==='account/read')return reply({account:{type:'chatgpt'}});
  if(r.method==='config/read')return reply({config:{mcp_servers:{unrelated:{enabled:true}}}});
  if(r.method==='thread/start'){
    writeFileSync(join(process.cwd(),'thread-fixture.json'),JSON.stringify(r.params));return reply({thread:{id:'image-thread'}});
  }
  if(r.method==='turn/start'){
    writeFileSync(join(process.cwd(),'../native-pid.txt'),String(process.pid));
    if(process.env.GAMESMITH_IMAGE_FIXTURE==='unexpected-edit')writeFileSync('unrelated.gd','unexpected');
    if(waiting())return reply({});
    emit({method:'item/completed',params:{item:{type:'imageGeneration',status:fail?'failed':'completed',result:fail?'':bytes.toString('base64')}}});
    emit({method:'turn/completed',params:{turn:{status:fail?'failed':'completed',error:fail?{message:'Fixture image limit'}:undefined}}});return reply({});
  }
  if(r.id!==undefined)reply({});
});
