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
  const native=join(dirname(found),'..','lib','opencode','tools','opencode.exe');
  if (harness==='opencode' && basename(found).toLowerCase()==='opencode.exe' && basename(dirname(found)).toLowerCase()==='bin' && existsSync(native)) found=resolve(native);
  if (/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  const entry=harness==='kilo' ? join(dirname(found),'node_modules','@kilocode','cli','bin','kilo') : join(dirname(found),'node_modules','opencode-ai','bin','opencode');
  if (!existsSync(entry)) throw new Error('Could not resolve '+label+' npm entry point.');
  return {bin:process.execPath,prefix:[entry]};
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
