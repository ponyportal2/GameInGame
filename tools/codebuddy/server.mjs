import {toolSpecs} from './workspace-tools.mjs';
import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_CODEBUDDY_BIN || 'codebuddy',platform=process.platform) {
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd|ps1)$/i.test(p));
  if(!found)throw new Error('CodeBuddy CLI was not found. Install @tencent-ai/codebuddy-code or set GAMESMITH_CODEBUDDY_BIN.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules/@tencent-ai/codebuddy-code/bin/codebuddy');
  if(!existsSync(entry))throw new Error('Could not resolve the CodeBuddy npm entry point. Set GAMESMITH_CODEBUDDY_BIN to the CodeBuddy executable.');
  return {bin:process.execPath,prefix:[entry]};
}
export function launchArgs(config){
  // Exact, non-deferred GameSmith tool registry; exclude native tools and other MCPs.
  // Keep user auth/model settings, ignore workspace/local policy and MCP files.
  return ['--acp','--tool-mode','cli','--tools',toolSpecs().map(t=>'NoDefer(mcp__gamesmith__'+t.name.slice(10)+')').join(','),'--strict-mcp-config','--mcp-config','{"mcpServers":{}}',
    '--permission-mode','default','--setting-sources','user','--append-system-prompt',readFileSync(config.prompt_path,'utf8')];
}
export class CodeBuddyServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
    this.cwd=join(dirname(config.session_file),'native-workspace');
  }
  get pid(){return this.child?.pid;}
  async start(){
    const exe=resolveExecutable();
    mkdirSync(this.cwd,{recursive:true});
    this.child=spawn(exe.bin,[...exe.prefix,...launchArgs(this.config)],{cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']});
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.stdin.on('error',()=>{});
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`CodeBuddy ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try{
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(!result.agentCapabilities?.loadSession)throw new Error('This CodeBuddy Code CLI cannot resume ACP sessions. Update CodeBuddy Code.');
      // Native provider credentials can work without CodeBuddy account OAuth.
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[{name:'gamesmith',_meta:{defer_loading:false},command:process.execPath,args:[this.config.mcp,this.config.config_path],env:[]}]};}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('CodeBuddy ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('CodeBuddy stopped.'));this.pending.clear();}
}
