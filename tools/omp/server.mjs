import {spawn,spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {join,resolve,basename} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createInterface} from 'node:readline';
const {killProcessTree}=await import(existsSync(new URL('./process-tree.mjs',import.meta.url)) ? './process-tree.mjs' : '../agent/process-tree.mjs');

export function resolveExecutable(bin=process.env.GAMESMITH_OMP_BIN || 'omp',platform=process.platform){
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('OMP was not found. Install OMP or set GAMESMITH_OMP_BIN to its executable.');
  return {bin:found,prefix:[]};
}
export function launchArgs(config){
  if(config.session && (basename(config.session)!==config.session || /[\\/]/.test(config.session) || !config.session.endsWith('.jsonl')))throw new Error('Invalid OMP session reference. Start a new OMP session in Settings.');
  return ['--mode','rpc','--no-ui','--no-tools','--no-extensions','--no-skills','--no-rules','--no-lsp','--no-title',
    '--session-dir',join(config.nativeRoot,'sessions'),'--system-prompt',config.prompt_path,
    '--extension',config.policy,'--config',config.overlay,
    ...(config.session ? ['--resume',join(config.nativeRoot,'sessions',config.session)] : [])];
}
export class OmpServer{
  constructor(config,{onEvent=()=>{},onStderr=()=>{},onExit=()=>{}}={}){
    Object.assign(this,{config,onEvent,onStderr,onExit});this.pending=new Map();this.serial=0;
  }
  get pid(){return this.child?.pid;}
  async start(tools){
    const c=this.config,exe=resolveExecutable(c.executable);c.nativeRoot=join(resolve(c.session_file,'..'),'native');
    mkdirSync(join(c.nativeRoot,'sessions'),{recursive:true});
    if(c.session && (basename(c.session)!==c.session || /[\\/]/.test(c.session) || !c.session.endsWith('.jsonl')))throw new Error('Invalid OMP session reference. Start a new OMP session in Settings.');
    if(c.session && !existsSync(join(c.nativeRoot,'sessions',c.session)))throw new Error('OMP session could not be resumed. Start a new OMP session in Settings. The previous reference and chat are kept.');
    c.policy=join(resolve(c.session_file,'..'),'policy.mjs');c.overlay=join(c.nativeRoot,'config.yml');
    // Preserve native model/auth/compaction. Disable unrelated autonomous activity
    // and tool discovery in this private run; exact activation is verified below.
    writeFileSync(c.overlay,JSON.stringify({tools:{xdev:false},advisor:{enabled:false},memory:{backend:'none'},prewalk:{enabled:false},mcp:{enableProjectConfig:false}}));
    this.nonce=randomUUID();this.policyFile=join(c.nativeRoot,'ready-'+this.nonce+'.json');
    const env={...process.env,GAMESMITH_OMP_POLICY:JSON.stringify({nonce:this.nonce,path:this.policyFile,tools:tools.map(t=>t.name)})};
    this.child=spawn(exe.bin,[...exe.prefix,...launchArgs(c)],{cwd:c.nativeRoot,env,windowsHide:true,stdio:['pipe','pipe','pipe']});
    const fail=error=>{for(const waiter of this.pending.values())waiter.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error('OMP exited with code '+code+'.')));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.type==='response'){
        const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);
        if(r.success)p.resolve(r.data || {});else p.reject(new Error(r.error || 'OMP rejected '+r.command));
      }else this.onEvent(r);
    });
    let timer;
    try{
      await Promise.race([this.initialize(tools),new Promise((_,reject)=>timer=setTimeout(()=>reject(new Error('OMP integration startup did not become ready within 30 seconds.')),30000))]);
    }catch(error){this.close();if(c.session)error.message+=' Start a new OMP session in Settings if the saved conversation cannot be resumed. The previous reference is kept.';throw error;}
    finally{clearTimeout(timer);}
  }
  async initialize(tools){
    this.state=await this.request('get_state');
    if(!this.state.sessionFile || !this.state.sessionId)throw new Error('OMP returned no persistent session.');
    if(this.config.session && basename(this.state.sessionFile)!==this.config.session)throw new Error('OMP resumed a different session.');
    const result=await this.request('set_host_tools',{tools});
    const expected=tools.map(t=>t.name).sort();
    if(JSON.stringify([...result.toolNames].sort())!==JSON.stringify(expected))throw new Error('OMP did not register the exact GameSmith tools.');
    await this.request('prompt',{message:'/gamesmith-ready'});
    // Extension commands acknowledge admission before their handler finishes.
    while(!existsSync(this.policyFile)){
      if(this.closing)throw new Error('OMP stopped during policy initialization.');
      await new Promise(resolve=>setTimeout(resolve,20));
    }
    const policy=JSON.parse(readFileSync(this.policyFile,'utf8'));
    if(policy.nonce!==this.nonce || JSON.stringify(policy.tools)!==JSON.stringify(expected))throw new Error('OMP GameSmith policy readiness did not match this runtime.');
  }
  send(r){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify(r)+'\n');}
  request(type,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('OMP backend is unavailable.'));
    const id='gs-'+ ++this.serial;
    return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,type,...params});});
  }
  close(){
    this.closing=true;
    if(this.child?.pid && this.child.exitCode===null)killProcessTree(this.child.pid);
    for(const p of this.pending.values())p.reject(new Error('OMP stopped.'));this.pending.clear();
  }
}
