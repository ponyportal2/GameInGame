import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';
import {nativeSettings} from './protocol.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_CLINE_BIN || 'cline',platform=process.platform) {
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd)$/i.test(p));
  if(!found)throw new Error('Cline CLI was not found. Install it and make cline available on PATH.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules/cline/bin/cline');
  if(!existsSync(entry))throw new Error('Could not resolve the Cline npm entry point.');
  return {bin:process.execPath,prefix:[entry]};
}
export class ClineServer {
  constructor(config,{onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported ACP request');},onExit=()=>{},onStderr=()=>{}}={}) {
    Object.assign(this,{config,onEvent,onRequest,onExit,onStderr});this.pending=new Map();this.serial=0;
  }
  get pid(){return this.child?.pid;}
  async start() {
    const native=nativeSettings(),directory=dirname(this.config.session_file),exe=resolveExecutable();this.settings=native;
    mkdirSync(join(directory,'native'),{recursive:true});
    // Provider credentials stay in Cline's original store, including OAuth refresh.
    // Only the MCP registry and session data are private to this game/runtime.
    const mcpPath=join(this.config.bridge_dir,'mcp.json');
    const quote=path=>process.platform==='win32' ? '"'+path+'"' : path;
    writeFileSync(mcpPath,JSON.stringify({mcpServers:{gamesmith:{command:quote(process.execPath),args:[quote(this.config.mcp),quote(this.config.config_path)]}}}));
    // Cline upgrades its own global npm install on startup, bypassing the
    // release-age gate (it passes --min-release-age 0). A game runtime must not
    // rewrite the user's toolchain mid-session, and the adapter is tested
    // against one version, so the child never self-updates.
    const env={...process.env,CLINE_PROVIDER_SETTINGS_PATH:native.providerPath,CLINE_SESSION_BACKEND_MODE:'local',
      CLINE_DATA_DIR:join(directory,'native'),CLINE_MCP_SETTINGS_PATH:mcpPath,CLINE_PROVIDER:native.provider,CLINE_NO_AUTO_UPDATE:'1'};
    if(native.model)env.CLINE_MODEL=native.model;
    // ACP restores OAuth itself, but its API-key providers require this env
    // input. Keep the credential in child memory, never runtime metadata/logs.
    if(!env.CLINE_API_KEY && !['cline','cline-pass','openai-codex'].includes(native.provider) && existsSync(native.providerPath)){
      const saved=JSON.parse(readFileSync(native.providerPath,'utf8')).providers?.[native.provider]?.settings;
      const key=saved?.auth?.accessToken || saved?.apiKey || saved?.auth?.apiKey;
      if(key)env.CLINE_API_KEY=key;
    }
    // Preserve native global choices (including compaction), without writing them.
    if(existsSync(native.globalPath))env.CLINE_GLOBAL_SETTINGS_PATH=native.globalPath;
    this.child=spawn(exe.bin,[...exe.prefix,'--acp','--auto-approve','false','--thinking',native.thinking],{cwd:this.config.workspace,env,windowsHide:true,stdio:['pipe','pipe','pipe']});
    const fail=error=>{for(const p of this.pending.values())p.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Cline ACP exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let r;try{r=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(r.method && r.id!==undefined)Promise.resolve().then(()=>this.onRequest(r.method,r.params || {})).then(result=>this.send({id:r.id,result}),error=>this.send({id:r.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      else if(r.id!==undefined){const p=this.pending.get(r.id);if(!p)return;this.pending.delete(r.id);r.error ? p.reject(new Error(r.error.data?.details || r.error.message)) : p.resolve(r.result);}
      else if(r.method)this.onEvent(r.method,r.params || {});
    });
    try {
      const result=await this.request('initialize',{protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}});
      if(!result.agentCapabilities?.loadSession)throw new Error('This Cline CLI does not support resumable ACP sessions. Update Cline.');
    }catch(error){this.close();throw error;}
  }
  send(record){if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',...record})+'\n');}
  request(method,params={}) {
    if(this.closing || !this.child || this.child.exitCode!==null)return Promise.reject(new Error('Cline ACP is unavailable.'));
    const id='gs-'+ ++this.serial;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.send({id,method,params});});
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const p of this.pending.values())p.reject(new Error('Cline stopped.'));this.pending.clear();}
}
