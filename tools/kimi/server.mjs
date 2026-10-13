import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {homedir} from 'node:os';
import {createInterface} from 'node:readline';
import {toolSpecs} from './workspace-tools.mjs';
import {killProcessTree} from './process-tree.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_KIMI_BIN || '',platform=process.platform) {
  if(!bin){const standard=join(process.env.USERPROFILE || homedir(),'.kimi-code','bin',platform==='win32'?'kimi.exe':'kimi');bin=existsSync(standard)?standard:'kimi';}
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('Kimi Code CLI was not found. Install Kimi Code or set GAMESMITH_KIMI_BIN to kimi.exe.');
  return {bin:found,prefix:[]};
}
export class KimiServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
    this.cwd=join(dirname(config.session_file),'native-workspace');
  }
  get pid(){return this.child?.pid;}
  async start(){
    const exe=resolveExecutable();
    mkdirSync(join(this.cwd,'.git'),{recursive:true});
    mkdirSync(join(this.cwd,'.kimi-code','agents'),{recursive:true});
    // Kimi emits structured arguments AFTER permission. Enforce the tool
    // boundary in its native agent profile instead of trusting display titles.
    const tools=toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10));
    writeFileSync(join(this.cwd,'.kimi-code','agents','agent.md'),'---\nname: agent\noverride: true\ndescription: GameSmith game editing\ntools: '+JSON.stringify(tools)+'\nsubagents: []\n---\n'+readFileSync(this.config.prompt_path,'utf8'));
    // Keep native provider/model/auth storage. The private cwd owns policy only.
    // MCP reload can wait for a human; progress notifications keep it active.
    const options={cwd:this.cwd,env:{...process.env,KIMI_MCP_TOOL_TIMEOUT_MS:'2147483647'},windowsHide:true,stdio:['pipe','pipe','pipe']};
    this.child=spawn(exe.bin,[...exe.prefix,'acp'],options);
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.stdin.on('error',()=>{});
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Kimi ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try{
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(result.agentInfo?.name!=='Kimi Code CLI')throw new Error('The selected executable is not Kimi Code CLI. Set GAMESMITH_KIMI_BIN to Kimi Code.');
      if(!result.agentCapabilities?.loadSession)throw new Error('This Kimi Code CLI cannot resume ACP sessions. Update Kimi Code.');
      // Native provider credentials can work without Kimi account OAuth.
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[{name:'gamesmith',command:process.execPath,args:[this.config.mcp,this.config.config_path],env:[]}]};}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Kimi ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Kimi stopped.'));this.pending.clear();}
}
