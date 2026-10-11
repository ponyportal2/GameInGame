import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve, dirname, join, basename } from 'node:path';
import { createInterface } from 'node:readline';
import { randomBytes } from 'node:crypto';
import http from 'node:http';

export function resolveExecutable(bin=process.env.GAMESMITH_OPENCODE_BIN || 'opencode', platform=process.platform) {
  if (/\.(mjs|js)$/i.test(bin) && existsSync(bin)) return {bin:process.execPath,prefix:[resolve(bin)]};
  if (platform!=='win32') return {bin,prefix:[]};
  let found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd)$/i.test(p));
  if (!found) throw new Error('OpenCode executable was not found.');
  const native=join(dirname(found),'..','lib','opencode','tools','opencode.exe');
  if (basename(found).toLowerCase()==='opencode.exe' && basename(dirname(found)).toLowerCase()==='bin' && existsSync(native)) found=resolve(native);
  if (/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules','opencode-ai','bin','opencode');
  if (!existsSync(entry)) throw new Error('Could not resolve OpenCode npm entry point.');
  return {bin:process.execPath,prefix:[entry]};
}

export class OpenCodeServer {
  constructor({workspace,executable,env=process.env,onStderr=()=>{},onExit=()=>{}}) {
    Object.assign(this,{workspace,executable,env,onStderr,onExit});
    this.password=randomBytes(32).toString('hex');this.requests=new Set();
  }
  get pid() {return this.child?.pid;}
  start() {
    if (this.starting) return this.starting;
    return this.starting=new Promise((resolveStart,reject)=>{
      const exe=resolveExecutable(this.executable);
      this.child=spawn(exe.bin,[...exe.prefix,'serve','--hostname','127.0.0.1','--port','0'],{cwd:this.workspace,windowsHide:true,detached:process.platform!=='win32',stdio:['ignore','pipe','pipe'],env:{...this.env,OPENCODE_SERVER_USERNAME:'opencode',OPENCODE_SERVER_PASSWORD:this.password}});
      this.child.once('error',reject);
      createInterface({input:this.child.stdout}).on('line',line=>{
        const match=line.match(/opencode server listening on (http:\/\/\S+)/);
        if (match) {this.url=match[1];resolveStart(this.url);}
      });
      createInterface({input:this.child.stderr}).on('line',this.onStderr);
      this.child.once('exit',code=>{
        const error=new Error(`OpenCode server exited with code ${code}.`);reject(error);
        for (const request of this.requests) request.destroy(error);
        this.onExit(error);
      });
    });
  }
  open(path,method,body,onResponse) {
    const data=body===undefined ? undefined : JSON.stringify(body);
    const request=http.request(new URL(path,this.url),{method,headers:{authorization:'Basic '+Buffer.from('opencode:'+this.password).toString('base64'),'x-opencode-directory':encodeURIComponent(this.workspace),...(data ? {'content-type':'application/json','content-length':Buffer.byteLength(data)} : {})}},onResponse);
    this.requests.add(request);request.once('close',()=>this.requests.delete(request));request.end(data);return request;
  }
  request(path,method='GET',body) {
    return new Promise((resolveResult,reject)=>{
      this.open(path,method,body,response=>{
        let text='';response.setEncoding('utf8');response.on('data',chunk=>text+=chunk);response.on('error',reject);
        response.on('end',()=>{
          try {const data=text ? JSON.parse(text) : null;
            if (response.statusCode>=300) throw new Error(data?.data?.message || data?.message || `OpenCode HTTP ${response.statusCode}`);
            resolveResult(data);
          } catch(error) {reject(error);}
        });
      }).once('error',reject);
    });
  }
  subscribe(onEvent,onError) {
    return new Promise((resolveSubscription,reject)=>{
      const request=this.open('/event','GET',undefined,response=>{
        if (response.statusCode!==200) {response.resume();reject(new Error('Could not subscribe to OpenCode events.'));return;}
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
