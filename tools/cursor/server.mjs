import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,mkdirSync,readdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {homedir} from 'node:os';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';

function packagedEntry(directory){
  if(existsSync(join(directory,'index.js')) && existsSync(join(directory,'node.exe')))return directory;
  const versions=join(directory,'versions');
  if(existsSync(versions))for(const version of readdirSync(versions).filter(v=>/^\d{4}\.\d{2}\.\d{2}/.test(v)).sort().reverse()){
    const found=packagedEntry(join(versions,version));if(found)return found;
  }
}
export function resolveExecutable(bin=process.env.GAMESMITH_CURSOR_BIN || '',platform=process.platform) {
  if(!bin){
    const standard=platform==='win32'?join(process.env.LOCALAPPDATA || join(homedir(),'AppData/Local'),'cursor-agent/cursor-agent.cmd'):join(homedir(),'.local/bin/cursor-agent');
    bin=existsSync(standard)?standard:'cursor-agent';
  }
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin)){
    const bundled=platform==='win32' && packagedEntry(dirname(resolve(bin)));
    return {bin:bundled?join(bundled,'node.exe'):process.execPath,prefix:[resolve(bin)]};
  }
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd|ps1)$/i.test(p));
  if(!found)throw new Error('Cursor Agent CLI was not found. Install the Cursor CLI (the desktop app alone is insufficient), or set GAMESMITH_CURSOR_BIN.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const directory=packagedEntry(dirname(found));
  if(!directory)throw new Error('Could not find Cursor CLI bundled node.exe and index.js. Set GAMESMITH_CURSOR_BIN to its installed entry point.');
  return {bin:join(directory,'node.exe'),prefix:[join(directory,'index.js')]};
}
export class CursorServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
    this.cwd=join(dirname(config.session_file),'native-workspace');
  }
  get pid(){return this.child?.pid;}
  async start(){
    const exe=resolveExecutable();
    mkdirSync(join(this.cwd,'.cursor'),{recursive:true});
    const deny=['Shell(*)','Write(**)','Read(**)','WebFetch(*)'];
    // Global MCP servers are still loaded by Cursor. Deny them at the native
    // policy layer too, including any native auto-approval configuration.
    const registry=join(homedir(),'.cursor/mcp.json');
    if(existsSync(registry))for(const name of Object.keys(JSON.parse(readFileSync(registry,'utf8')).mcpServers || {}))if(name!=='gamesmith')deny.push(`Mcp(${name}:*)`);
    writeFileSync(join(this.cwd,'.cursor/cli.json'),JSON.stringify({permissions:{allow:[],deny}}));
    const options={cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']};
    // ACP authenticate can open a browser when logged out. Report actionable
    // login guidance first; this child is also owned by the Stop process tree.
    this.child=spawn(exe.bin,[...exe.prefix,'status','--format','json'],options);
    const status=await new Promise((resolve,reject)=>{
      let output='';this.statusReject=reject;
      this.child.stdout.on('data',d=>output+=d);this.child.stderr.resume();
      this.child.once('error',reject);
      this.child.once('exit',()=>{try{resolve(JSON.parse(output));}catch{reject(new Error('Could not check Cursor CLI login. Run cursor-agent status, then cursor-agent login.'));}});
    });
    this.statusReject=undefined;
    if(this.closing)throw new Error('Cursor stopped.');
    if(!status.isAuthenticated)throw new Error('Cursor CLI is not logged in. Run cursor-agent login, then send your message again.');
    this.child=spawn(exe.bin,[...exe.prefix,'acp'],options);
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Cursor ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error?p.reject(new Error(r.error.data?.details || r.error.message)):p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try{
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(!result.agentCapabilities?.loadSession)throw new Error('This Cursor CLI cannot resume ACP sessions. Update Cursor CLI.');
      await this.request('authenticate',{methodId:'cursor_login'});
    }catch(error){this.close();throw error;}
  }
  sessionParams(){return {cwd:this.cwd,mcpServers:[{name:'gamesmith',command:process.execPath,args:[this.config.mcp,this.config.config_path],env:[]}]};}
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}){
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Cursor ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;this.statusReject?.(new Error('Cursor stopped.'));if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Cursor stopped.'));this.pending.clear();}
}
