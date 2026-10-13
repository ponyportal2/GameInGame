import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,mkdirSync,readdirSync,unlinkSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {homedir} from 'node:os';
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import {toolSpecs} from './workspace-tools.mjs';
import {killProcessTree} from './process-tree.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_COPILOT_BIN || 'copilot',platform=process.platform) {
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd|ps1)$/i.test(p));
  if(!found)throw new Error('Copilot CLI was not found. Install GitHub Copilot CLI or set GAMESMITH_COPILOT_BIN.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules','@github','copilot','npm-loader.js');
  if(!existsSync(entry))throw new Error('Could not resolve the GitHub Copilot npm entry point. Set GAMESMITH_COPILOT_BIN to copilot.exe.');
  return {bin:process.execPath,prefix:[entry]};
}
export class CopilotServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
    this.cwd=join(dirname(config.session_file),'native-workspace');
    this.agentId='gamesmith-'+randomUUID();
  }
  get pid(){return this.child?.pid;}
  async start(){
    const exe=resolveExecutable();
    mkdirSync(join(this.cwd,'.github','agents'),{recursive:true});
    const names=toolSpecs().map(t=>'gamesmith-'+t.name.slice(10));
    // Both ACP startup filtering and the selected custom profile limit tools.
    // Model, credentials, reasoning and compaction stay native-owned.
    writeFileSync(join(this.cwd,'.github','agents',this.agentId+'.agent.md'),
      '---\nname: '+this.agentId+'\ndescription: GameSmith game editing\ntools: '+JSON.stringify(names)+'\n---\n'+readFileSync(this.config.prompt_path,'utf8'));
    const mcpPath=join(dirname(this.config.session_file),'mcp-config.json');
    writeFileSync(mcpPath,JSON.stringify({mcpServers:{gamesmith:{type:'local',command:process.execPath,args:[this.config.mcp,this.config.config_path],tools:['*'],timeout:2147483647}}}));
    const options={cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']};
    this.child=spawn(exe.bin,[...exe.prefix,'--acp','--stdio','--disable-builtin-mcps','--no-auto-update','--no-ask-user','--no-remote',
      '--available-tools='+names.map(n=>'mcp:'+n).join(','),'--allow-tool=gamesmith','--additional-mcp-config=@'+mcpPath],options);
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.stdin.on('error',()=>{});
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Copilot ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try{
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(result.agentInfo?.name!=='Copilot')throw new Error('The selected executable is not GitHub Copilot CLI. Set GAMESMITH_COPILOT_BIN to Copilot CLI.');
      if(!result.agentCapabilities?.loadSession)throw new Error('This GitHub Copilot CLI cannot resume ACP sessions. Update Copilot CLI.');
      // Login and selected model stay in Copilot's native configuration.
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[]};}
  cleanupProfiles(){
    // Resume may still refer to the previous agent. Call only after loading the
    // conversation and verifying the fresh agent selection; never on close.
    const directory=join(this.cwd,'.github','agents');
    const generated=/^gamesmith-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.agent\.md$/;
    try{
      for(const entry of readdirSync(directory,{withFileTypes:true})){
        if(!entry.isFile() || entry.name===this.agentId+'.agent.md' || !generated.test(entry.name))continue;
        try{unlinkSync(join(directory,entry.name));}
        catch(error){this.onStderr('Could not remove obsolete Copilot profile: '+error.message);}
      }
    }catch(error){this.onStderr('Could not scan obsolete Copilot profiles: '+error.message);}
  }
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Copilot ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Copilot stopped.'));this.pending.clear();}
}
