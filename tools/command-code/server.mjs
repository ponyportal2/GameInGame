import {spawn,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,existsSync,mkdirSync} from 'node:fs';
import {homedir} from 'node:os';
import {dirname,join,resolve} from 'node:path';
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import {killProcessTree} from './process-tree.mjs';
import {validReady} from './policy.mjs';

// ACP 1.86.3 still skips root CLI --mod options. Native user-mod discovery is
// supported. This inert loader never changes terminal sessions or native settings.
export const LOADER = `export default async function(cmd) {
  if(process.env.GAMESMITH_COMMAND_ACP !== 'v1' || !process.env.GAMESMITH_POLICY_NONCE || !process.env.GAMESMITH_POLICY_MOD) return;
  const {pathToFileURL} = await import('node:url');
  const mod = await import(pathToFileURL(process.env.GAMESMITH_POLICY_MOD).href);
  await mod.default(cmd);
}\n`;
export function executable() {
  const bin=process.env.GAMESMITH_COMMAND_CODE_BIN || 'command-code';
  if(existsSync(bin) && /\.(mjs|js)$/i.test(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(process.platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(cmd|exe)$/i.test(p));
  if(!found)throw new Error('Command-code executable was not found. Install command-code@1.86.3 or set GAMESMITH_COMMAND_CODE_BIN.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules','command-code','dist','index.mjs');
  if(!existsSync(entry))throw new Error('Could not resolve Command-code npm entry point. Set GAMESMITH_COMMAND_CODE_BIN to dist/index.mjs.');
  return {bin:process.execPath,prefix:[entry]};
}
export class CommandServer {
  constructor(config,handlers){Object.assign(this,{config,...handlers});this.pending=new Map();this.serial=0;this.nonce=randomUUID();this.readyFile=join(config.bridge_dir,'ready-'+this.nonce+'.json');this.readyCommand='gamesmith-ready-'+this.nonce;}
  get pid(){return this.child?.pid;}
  async start(){
    // Native ACP resume uses os.homedir(), even when its writer sees HOME.
    // Keep both sides on the same native root so session/load cannot lose history.
    const home=homedir(),mods=join(home,'.commandcode','mods');mkdirSync(mods,{recursive:true});
    const loader=join(mods,'gamesmith-acp-loader-v1.ts');
    try{writeFileSync(loader,LOADER,{flag:'wx'});}catch(error){if(error.code!=='EEXIST')throw error;if(readFileSync(loader,'utf8')!==LOADER)throw new Error('GameSmith ACP loader differs from the supported version. Refusing to overwrite it.');}
    const exe=executable();this.child=spawn(exe.bin,[...exe.prefix,'acp'],{cwd:this.config.workspace,windowsHide:true,stdio:['pipe','pipe','pipe'],
      env:{...process.env,HOME:home,USERPROFILE:home,COMMANDCODE_SKIP_UPDATES:'1',GAMESMITH_COMMAND_ACP:'v1',GAMESMITH_POLICY_NONCE:this.nonce,GAMESMITH_POLICY_MOD:this.config.mod,GAMESMITH_POLICY_READY:this.readyFile,
        GAMESMITH_HOST_BRIDGE_DIR:this.config.bridge_dir,GAMESMITH_PROMPT_PATH:this.config.prompt_path}});
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error('Command-code ACP exited: '+code)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.type==='gamesmith_policy' && r.nonce===this.nonce){this.onPolicy(r.event);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1'}});
    if(result.agentInfo?.name!=='Command Code' || result.agentInfo.version!=='1.86.3')throw new Error('GameSmith ACP requires tested command-code@1.86.3. Run npm install -g command-code@1.86.3.');
    if(!result.agentCapabilities?.loadSession)throw new Error('Command-code must support resumable ACP sessions. Use tested version 1.86.3.');
    await this.waitReady('loaded');return result;
  }
  async waitReady(phase){for(;;){if(this.closing)throw new Error('Command-code policy readiness was cancelled.');try{if(validReady(JSON.parse(readFileSync(this.readyFile,'utf8')),this.nonce,phase))return;}catch(error){if(error.code!=='ENOENT' && !(error instanceof SyntaxError))throw error;}await new Promise(r=>setTimeout(r,20));}}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Command-code ACP is unavailable.'));const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});}
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Command-code stopped.'));this.pending.clear();}
}
