import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, dirname, join, basename } from 'node:path';
import { createInterface } from 'node:readline';
import { randomBytes } from 'node:crypto';
import http from 'node:http';

export function resolveExecutable(bin, platform=process.platform, harness='opencode') {
  const label=harness==='kilo' ? 'Kilo' : 'OpenCode';
  bin ||= process.env[harness==='kilo' ? 'GAMESMITH_KILO_BIN' : 'GAMESMITH_OPENCODE_BIN'] || harness;
  if (/\.(mjs|js)$/i.test(bin) && existsSync(bin)) return {bin:process.execPath,prefix:[resolve(bin)]};
  if (platform!=='win32') return {bin,prefix:[]};
  let found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd)$/i.test(p));
  if (!found) throw new Error(label+' executable was not found.');
  const directory=dirname(found);
  // The npm launcher is a batch shim in front of a native single-file binary.
  // Spawning the shim would leave a transient cmd.exe parent in the tree.
  const native=harness==='opencode' ? [
    join(directory,'node_modules','@opencode','cli','bin','opencode.exe'),
    join(directory,'..','lib','opencode','tools','opencode.exe'),
  ].find(candidate=>existsSync(candidate)) : undefined;
  if (native) found=resolve(native);
  if (/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  if (harness==='kilo') {
    const entry=join(directory,'node_modules','@kilocode','cli','bin','kilo');
    if (existsSync(entry)) return {bin:process.execPath,prefix:[entry]};
    throw new Error('Could not resolve Kilo npm entry point.');
  }
  throw new Error('Could not resolve OpenCode 2 executable. Install the OpenCode 2 CLI or set GAMESMITH_OPENCODE_BIN to its native binary.');
}

const ACP_INITIALIZE={protocolVersion:1,clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false},clientInfo:{name:'gamesmith',version:'1.0.0'}};

// OpenCode 2 speaks ACP over newline-delimited JSON-RPC on stdio. There is no
// HTTP listener, so the session, the cancel path and the event stream all live
// on the same child process.
export class OpenCodeAcpServer {
  constructor({workspace,executable,env=process.env,onStderr=()=>{},onExit=()=>{}}) {
    Object.assign(this,{workspace,executable,env,onStderr,onExit});
    this.label='OpenCode';this.pending=new Map();this.listeners=new Set();this.serial=0;this.stopping=false;
  }
  get pid() {return this.child?.pid;}
  get running() {return !!this.child && this.child.exitCode===null;}
  start() {
    if (this.starting) return this.starting;
    return this.starting=new Promise((resolveStart,reject)=>{
      let exe;
      try {exe=resolveExecutable(this.executable,process.platform,'opencode');}
      catch (error) {reject(error);return;}
      this.child=spawn(exe.bin,[...exe.prefix,'acp'],{cwd:this.workspace,windowsHide:true,detached:process.platform!=='win32',stdio:['pipe','pipe','pipe'],env:this.env});
      this.child.once('error',error=>{this.rejectPending(error);reject(error);});
      createInterface({input:this.child.stdout}).on('line',line=>this.receive(line));
      createInterface({input:this.child.stderr}).on('line',this.onStderr);
      this.child.once('exit',code=>{
        const error=new Error(`${this.label} backend exited with code ${code}.`);
        this.rejectPending(error);
        if (!this.stopping) this.onExit(error);
      });
      this.request('initialize',ACP_INITIALIZE).then(result=>{
        this.capabilities=result?.agentCapabilities || {};
        resolveStart(this);
      },reject);
    });
  }
  receive(line) {
    let message;
    try {message=JSON.parse(line);} catch {return;}
    if (message.method && message.id!==undefined) {this.respond(message);return;}
    if (message.id!==undefined) {
      const pending=this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message || this.label+' request failed.'));
      else pending.resolve(message.result);
      return;
    }
    if (message.method==='session/update') {
      const params=message.params || {};
      for (const listener of this.listeners) listener(params.update || {},params);
    }
  }
  respond(message) {
    // GameSmith only grants what its configuration already allowed. An
    // unexpected prompt is refused rather than approved on the player's behalf.
    const result=message.method==='session/request_permission' ? {outcome:{outcome:'cancelled'}} : undefined;
    const payload=result
      ? {jsonrpc:'2.0',id:message.id,result}
      : {jsonrpc:'2.0',id:message.id,error:{code:-32601,message:'Method not supported: '+message.method}};
    this.child?.stdin.write(JSON.stringify(payload)+'\n');
  }
  request(method,params) {
    return new Promise((resolveResult,reject)=>{
      if (!this.running) {reject(new Error(this.label+' backend is not running.'));return;}
      const id=++this.serial;
      this.pending.set(id,{resolve:resolveResult,reject});
      this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');
    });
  }
  notify(method,params) {
    if (this.running) this.child.stdin.write(JSON.stringify({jsonrpc:'2.0',method,params})+'\n');
  }
  onUpdate(listener) {
    this.listeners.add(listener);
    return ()=>this.listeners.delete(listener);
  }
  rejectPending(error) {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
  async close() {
    this.stopping=true;
    try {this.child?.stdin.end();} catch {}
    if (this.child?.pid) {
      if (process.platform==='win32') spawnSync('taskkill.exe',['/PID',String(this.child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
      else {try {process.kill(-this.child.pid,'SIGTERM');} catch {}}
    }
    this.rejectPending(new Error(this.label+' backend closed.'));
  }
}

export class OpenCodeServer {
  constructor({workspace,executable,harness='opencode',env=process.env,onStderr=()=>{},onExit=()=>{}}) {
    Object.assign(this,{workspace,executable,env,onStderr,onExit});
    this.harness=harness;this.label=harness==='kilo' ? 'Kilo' : 'OpenCode';this.prefix=harness==='kilo' ? 'KILO' : 'OPENCODE';this.directoryHeader='x-'+harness+'-directory';
    this.password=randomBytes(32).toString('hex');this.requests=new Set();
  }
  get pid() {return this.child?.pid;}
  start() {
    if (this.starting) return this.starting;
    return this.starting=new Promise((resolveStart,reject)=>{
      const exe=resolveExecutable(this.executable,process.platform,this.harness);
      this.child=spawn(exe.bin,[...exe.prefix,'serve','--hostname','127.0.0.1','--port','0'],{cwd:this.workspace,windowsHide:true,detached:process.platform!=='win32',stdio:['ignore','pipe','pipe'],env:{...this.env,[this.prefix+'_SERVER_USERNAME']:this.harness,[this.prefix+'_SERVER_PASSWORD']:this.password}});
      this.child.once('error',reject);
      createInterface({input:this.child.stdout}).on('line',line=>{
        const match=line.match(new RegExp('^'+this.harness+' server listening on (http://\\S+)'));
        if (match) {this.url=match[1];resolveStart(this.url);}
      });
      createInterface({input:this.child.stderr}).on('line',this.onStderr);
      this.child.once('exit',code=>{
        const error=new Error(`${this.label} server exited with code ${code}.`);reject(error);
        for (const request of this.requests) request.destroy(error);
        this.onExit(error);
      });
    });
  }
  open(path,method,body,onResponse) {
    const data=body===undefined ? undefined : JSON.stringify(body);
    const url=new URL(path,this.url),queryDirectory=this.harness==='kilo' && ['GET','HEAD'].includes(method);
    if(queryDirectory)url.searchParams.set('directory',this.workspace);
    const request=http.request(url,{method,headers:{authorization:'Basic '+Buffer.from(this.harness+':'+this.password).toString('base64'),...(!queryDirectory ? {[this.directoryHeader]:encodeURIComponent(this.workspace)} : {}),...(data ? {'content-type':'application/json','content-length':Buffer.byteLength(data)} : {})}},onResponse);
    this.requests.add(request);request.once('close',()=>this.requests.delete(request));request.end(data);return request;
  }
  request(path,method='GET',body) {
    return new Promise((resolveResult,reject)=>{
      this.open(path,method,body,response=>{
        let text='';response.setEncoding('utf8');response.on('data',chunk=>text+=chunk);response.on('error',reject);
        response.on('end',()=>{
          try {const data=text ? JSON.parse(text) : null;
            if (response.statusCode>=300) throw new Error(data?.data?.message || data?.message || `${this.label} HTTP ${response.statusCode}`);
            resolveResult(data);
          } catch(error) {reject(error);}
        });
      }).once('error',reject);
    });
  }
  subscribe(onEvent,onError) {
    return new Promise((resolveSubscription,reject)=>{
      const request=this.open('/event','GET',undefined,response=>{
        if (response.statusCode!==200) {response.resume();reject(new Error('Could not subscribe to '+this.label+' events.'));return;}
        let data=[], closed=false;
        createInterface({input:response}).on('error',error=>{if (!closed) onError(error);}).on('line',line=>{
          if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
          else if (!line && data.length) {try {onEvent(JSON.parse(data.join('\n')));} catch(error) {onError(error);}data=[];}
        });
        response.on('error',error=>{if (!closed) onError(error);});resolveSubscription(()=>{closed=true;request.destroy();});
      });
      request.once('error',reject);
    });
  }
  async close() {
    if (this.child?.pid) {
      if (process.platform==='win32') spawnSync('taskkill.exe',['/PID',String(this.child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
      else {try {process.kill(-this.child.pid,'SIGTERM');} catch {}}
    }
    for (const request of this.requests) request.destroy();
  }
}
