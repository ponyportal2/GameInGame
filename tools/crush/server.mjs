import {spawn,spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {createServer} from 'node:net';
import {createInterface} from 'node:readline';
import {randomUUID} from 'node:crypto';
import http from 'node:http';
import {toolSpecs} from './workspace-tools.mjs';
import {killProcessTree} from './process-tree.mjs';

// Validate the resolved native tool list as well: a new built-in must fail
// closed until the policy is updated for that Crush version.
export const disabledTools=['agent','bash','crush_info','crush_logs','job_output','job_kill','download','edit','multiedit','lsp_diagnostics','lsp_references','lsp_restart','lsp_symbols','lsp_definition','lsp_call_hierarchy','lsp_rename','lsp_replace_symbol','fetch','agentic_fetch','glob','grep','ls','question','sourcegraph','todos','view','write','list_mcp_resources','read_mcp_resource'];
export function resolveExecutable(bin=process.env.GAMESMITH_CRUSH_BIN || 'crush',platform=process.platform){
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('Crush CLI was not found. Install Crush or set GAMESMITH_CRUSH_BIN to crush.exe.');
  return {bin:found,prefix:[]};
}
export function policy(config,global={}){
  const names=toolSpecs().map(t=>t.name.slice(10)),mcp={};
  for(const name of Object.keys(global.mcp || {}))if(name!=='gamesmith')mcp[name]={disabled:true};
  mcp.gamesmith={type:'stdio',command:process.execPath,args:[config.mcp,config.config_path],enabled_tools:names,disabled_tools:[],disabled:false,timeout:2147483647};
  return {options:{disabled_tools:disabledTools,context_paths:[config.prompt_path],auto_lsp:false},permissions:{allowed_tools:names.map(n=>'mcp_gamesmith_'+n)},mcp};
}
export function verifyPolicy(config,expected){
  if(!disabledTools.every(name=>config?.options?.disabled_tools?.includes(name)))throw new Error('Crush did not restrict native tools to GameSmith MCP. Update the GameSmith Crush adapter.');
  if(config.options?.auto_lsp!==false || !config.mcp?.gamesmith || config.mcp.gamesmith.disabled || Object.entries(config.mcp).some(([name,value])=>name!=='gamesmith' && !value.disabled))throw new Error('Crush did not load the restricted GameSmith MCP configuration.');
  const actual=config.mcp.gamesmith,wanted=expected.mcp.gamesmith;
  if(actual.command!==wanted.command || JSON.stringify(actual.args)!==JSON.stringify(wanted.args) || JSON.stringify(actual.enabled_tools)!==JSON.stringify(wanted.enabled_tools))throw new Error('Crush merged an incompatible gamesmith MCP configuration. Remove the conflicting native gamesmith server configuration and retry.');
}
async function freePort(){const socket=createServer();await new Promise((resolve,reject)=>{socket.once('error',reject);socket.listen(0,'127.0.0.1',resolve);});const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));return port;}
export class CrushServer {
  constructor(config,{onEvent=()=>{},onExit=()=>{},onStderr=()=>{}}={}){
    Object.assign(this,{config,onEvent,onExit,onStderr});this.requests=new Set();this.client=randomUUID();
    this.cwd=join(dirname(config.session_file),'native-workspace');this.data=join(dirname(config.session_file),'native-data');
  }
  get pid(){return this.child?.pid;}
  async start(){
    mkdirSync(this.cwd,{recursive:true});mkdirSync(this.data,{recursive:true});
    const exe=resolveExecutable(),port=await freePort();if(this.closing)throw new Error('Crush stopped.');
    this.url='http://127.0.0.1:'+port;
    this.child=spawn(exe.bin,[...exe.prefix,'server','--host','tcp://127.0.0.1:'+port,'--data-dir',join(dirname(this.config.session_file),'server-data')],{cwd:this.cwd,env:{...process.env},windowsHide:true,stdio:['ignore','pipe','pipe']});
    this.child.once('error',error=>{this.failure=error;if(!this.closing)this.onExit(error);});
    this.child.once('exit',code=>{this.failure=new Error('Crush server exited with code '+code+'.');if(!this.closing)this.onExit(this.failure);});
    createInterface({input:this.child.stdout}).on('line',this.onStderr);createInterface({input:this.child.stderr}).on('line',this.onStderr);
    try{
      // Readiness polling has no agent deadline; host Stop supplies its grace.
      while(!this.closing && !this.failure){try{await this.request('/v1/health');break;}catch(error){if(!['ECONNREFUSED','ECONNRESET'].includes(error.code))throw error;await new Promise(resolve=>setTimeout(resolve,50));}}
      if(this.closing || this.failure)throw this.failure || new Error('Crush stopped.');
      const version=await this.request('/v1/version');this.version=version.version;
      // Agents.AllowedTools is deliberately omitted from native JSON. The
      // exact tested version plus resolved disabled_tools verifies its fixed
      // built-in registry; unknown versions cannot silently add native tools.
      if(!/^v?0\.96\.1$/.test(this.version || ''))throw new Error('This GameSmith adapter supports Crush CLI 0.96.1. The installed version is '+this.version+'. Update the adapter before using a different Crush version.');
      const global=await this.request('/v1/config'),overlay=policy(this.config,global);
      // Data overrides have highest priority. Crush concatenates arrays when
      // merging scopes: install policy once, without copying credentials.
      writeFileSync(join(this.data,'crush.json'),JSON.stringify(overlay));
      const workspace=await this.request('/v1/workspaces','POST',{path:this.cwd,data_dir:this.data,client_id:this.client,yolo:false});
      verifyPolicy(workspace.config,overlay);if(workspace.yolo)throw new Error('Crush unexpectedly enabled unrestricted permissions.');
      this.workspace=workspace.id;if(!this.workspace)throw new Error('Crush returned no workspace ID.');
      await this.subscribe();
    }catch(error){this.close();throw error;}
  }
  path(path){if(!this.workspace)throw new Error('Crush workspace is unavailable.');return '/v1/workspaces/'+encodeURIComponent(this.workspace)+path;}
  request(path,method='GET',body){
    if(this.closing)return Promise.reject(new Error('Crush stopped.'));
    return new Promise((resolve,reject)=>{
      const data=body===undefined ? undefined : JSON.stringify(body);
      const request=http.request(new URL(path,this.url),{method,headers:data?{'content-type':'application/json','content-length':Buffer.byteLength(data)}:{}},response=>{
        let text='';response.setEncoding('utf8');response.on('data',chunk=>text+=chunk);response.once('error',reject);response.once('aborted',()=>reject(new Error('Crush HTTP response was interrupted.')));
        response.once('end',()=>{try{const result=text ? JSON.parse(text):null;if(response.statusCode>=300)throw new Error(result?.message || 'Crush HTTP '+response.statusCode);resolve(result);}catch(error){reject(error);}});
      });
      this.requests.add(request);request.once('close',()=>this.requests.delete(request));request.once('error',reject);request.end(data);
    });
  }
  subscribe(){
    return new Promise((resolve,reject)=>{
      const request=http.get(new URL(this.path('/events')+'?client_id='+encodeURIComponent(this.client),this.url),response=>{
        if(response.statusCode!==200){response.resume();reject(new Error('Could not subscribe to Crush events.'));return;}
        let data=[];const fail=error=>{if(!this.closing)this.onExit(error);};
        createInterface({input:response}).on('error',fail).on('line',line=>{
          if(line.startsWith('data:'))data.push(line.slice(5).trimStart());
          else if(!line && data.length){try{this.onEvent(JSON.parse(data.join('\n')));}catch(error){fail(error);}data=[];}
        });
        response.once('error',fail);response.once('end',()=>fail(new Error('Crush live event stream ended before shutdown.')));resolve();
      });
      this.requests.add(request);request.once('close',()=>this.requests.delete(request));request.once('error',reject);
    });
  }
  close(){if(this.closing)return;this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);for(const request of this.requests)request.destroy(new Error('Crush stopped.'));}
}
