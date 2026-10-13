import {spawn,spawnSync} from 'node:child_process';
import {existsSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';
import {homedir} from 'node:os';

export function resolveExecutable(bin=process.env.GAMESMITH_GROK_BUILD_BIN || '',platform=process.platform) {
  if(!bin){const installed=join(homedir(),'.grok','bin',platform==='win32'?'grok.exe':'grok');bin=platform==='win32' && existsSync(installed)?installed:'grok';}
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('Grok Build CLI was not found. Install Grok Build or set GAMESMITH_GROK_BUILD_BIN to grok.exe. The generic agent command is ambiguous.');
  return {bin:found,prefix:[]};
}
export class GrokBuildServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}) {
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
  }
  get pid(){return this.child?.pid;}
  async start() {
    const exe=resolveExecutable();
    this.cwd=join(dirname(this.config.session_file),'native-workspace');
    mkdirSync(join(this.cwd,'.grok'),{recursive:true});
    // Native tool restrictions apply even when the ordinary CLI is auto-approved.
    // MCP calls must still match the active ACP permission announcement.
    writeFileSync(join(this.cwd,'.grok/config.toml'),'[permission]\nask = ["MCPTool(*)"]\ndeny = ["Bash", "Read", "Edit", "Write", "Grep", "Glob", "WebFetch", "WebSearch"]\n');
    this.child=spawn(exe.bin,[...exe.prefix,'--tools','use_tool,search_tool','--no-subagents','--disable-web-search','--permission-mode','default','agent','--no-leader','stdio'],{cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']});
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Grok Build ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error ? p.reject(new Error(r.error.data?.details || r.error.message)) : p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try {
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(result._meta?.grokShell!==true || !result.authMethods?.some(m=>m.id==='cached_token'))throw new Error('The selected executable is not Grok Build CLI. Use grok or set GAMESMITH_GROK_BUILD_BIN to Grok Build; choose Cursor separately.');
      if(!result.agentCapabilities?.loadSession)throw new Error('This Grok Build CLI does not support resumable ACP sessions. Update Grok Build.');
      await this.request('authenticate',{methodId:'cached_token'});
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[{name:'gamesmith',command:process.execPath,args:[this.config.mcp,this.config.config_path],env:[]}],_meta:{yoloMode:false,autoMode:false}};}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}) {
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Grok Build ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Grok Build stopped.'));this.pending.clear();}
}
