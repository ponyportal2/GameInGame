import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {homedir} from 'node:os';
import {createInterface} from 'node:readline';
import {toolSpecs} from './workspace-tools.mjs';
import {killProcessTree} from './process-tree.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_KIRO_BIN || '',platform=process.platform) {
  if(!bin){const standard=platform==='win32'?join(process.env.LOCALAPPDATA || join(homedir(),'AppData','Local'),'Kiro-Cli','kiro-cli.exe'):join(homedir(),'.local','bin','kiro-cli');bin=existsSync(standard)?standard:'kiro-cli';}
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('Kiro CLI Agent was not found. Install Kiro CLI or set GAMESMITH_KIRO_BIN to kiro-cli.exe.');
  return {bin:found,prefix:[]};
}
export class KiroServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
    this.cwd=join(dirname(config.session_file),'native-workspace');
  }
  get pid(){return this.child?.pid;}
  async start(){
    const exe=resolveExecutable();
    mkdirSync(join(this.cwd,'.kiro','agents'),{recursive:true});
    // V3 profile selectors enforce the executable tool boundary before consent.
    // No global MCP, native tools, model/provider/reasoning or auth overrides.
    // V3 only discovers a workspace agent when the file is in its universal
    // shape, so the empty rule list is required even though it grants nothing.
    const profile={name:'gamesmith',description:'GameSmith game editing',prompt:readFileSync(this.config.prompt_path,'utf8'),
      tools:toolSpecs().map(t=>'@gamesmith/'+t.name.slice(10)),allowedTools:[],includeMcpJson:false,permissions:{rules:[]},
      mcpServers:{gamesmith:{command:process.execPath,args:[this.config.mcp,this.config.config_path],timeout:2147483647}}};
    writeFileSync(join(this.cwd,'.kiro','agents','gamesmith.json'),JSON.stringify(profile));
    const options={cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']};
    // V3 selects the custom agent as a session mode and rejects --agent.
    this.child=spawn(exe.bin,[...exe.prefix,'acp','--agent-engine','v3'],options);
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.stdin.on('error',()=>{});
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Kiro ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try{
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      // V3 omits agentInfo; its extension list is the engine-specific marker.
      if(result.agentInfo?.name!=='Kiro CLI Agent' && !Array.isArray(result.agentCapabilities?._meta?.kiro?.extensionMethods))throw new Error('The selected executable is not Kiro CLI Agent. Set GAMESMITH_KIRO_BIN to Kiro CLI.');
      if(!result.agentCapabilities?.loadSession)throw new Error('This Kiro CLI Agent cannot resume ACP sessions. Update Kiro CLI.');
      // Login and selected model stay in Kiro's native configuration.
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[]};}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Kiro ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Kiro stopped.'));this.pending.clear();}
}
