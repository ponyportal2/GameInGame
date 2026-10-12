import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { killProcessTree } from './process-tree.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_CODEX_BIN || 'codex',platform=process.platform) {
  if (/\.(mjs|js)$/i.test(bin) && existsSync(bin)) return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32') return {bin,prefix:[]};
  const found=existsSync(bin) ? resolve(bin) : spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd)$/i.test(p));
  if(!found) throw new Error('Codex CLI was not found. Install it and make codex available on PATH.');
  if(/\.exe$/i.test(found)) return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules','@openai','codex','bin','codex.js');
  if(!existsSync(entry)) throw new Error('Could not resolve the Codex npm entry point.');
  return {bin:process.execPath,prefix:[entry]};
}

export class CodexServer {
  constructor({workspace,executable,onEvent=()=>{},onRequest=async()=>{throw new Error('Unsupported Codex request');},onStderr=()=>{},onExit=()=>{}}) {
    Object.assign(this,{workspace,executable,onEvent,onRequest,onStderr,onExit});this.pending=new Map();this.serial=0;
  }
  get pid() {return this.child?.pid;}
  async start() {
    const exe=resolveExecutable(this.executable);
    this.child=spawn(exe.bin,[...exe.prefix,'app-server','--stdio'],{cwd:this.workspace,windowsHide:true,stdio:['pipe','pipe','pipe']});
    const fail=error=>{for(const waiter of this.pending.values()) waiter.reject(error);this.pending.clear();if(!this.closing)this.onExit(error);};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error(`Codex app-server exited with code ${code}.`)));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let record;try{record=JSON.parse(line);}catch{this.onStderr(line);return;}
      if(record.method && record.id!==undefined) {
        Promise.resolve().then(()=>this.onRequest(record.method,record.params || {})).then(result=>this.send({id:record.id,result}),
          error=>this.send({id:record.id,error:{code:-32601,message:error.message}})).catch(()=>{});
      } else if(record.id!==undefined) {
        const pending=this.pending.get(record.id);if(!pending)return;this.pending.delete(record.id);
        if(record.error) pending.reject(new Error(record.error.message));else pending.resolve(record.result);
      } else if(record.method) this.onEvent(record.method,record.params || {});
    });
    try {
      await this.request('initialize',{clientInfo:{name:'gamesmith',title:'GameSmith',version:'1.0.0'},capabilities:{experimentalApi:true}});
      this.send({method:'initialized'});
    } catch(error) {this.close();throw error;}
  }
  send(record) {if(this.child?.stdin.writable)this.child.stdin.write(JSON.stringify(record)+'\n');}
  request(method,params={}) {
    if(this.closing || !this.child || this.child.exitCode!==null) return Promise.reject(new Error('Codex app-server is unavailable.'));
    const id='gs-'+ ++this.serial;
    return new Promise((resolveResult,reject)=>{this.pending.set(id,{resolve:resolveResult,reject});this.send({id,method,params});});
  }
  close() {
    this.closing=true;
    if(this.child?.pid && this.child.exitCode===null) killProcessTree(this.child.pid);
    for(const pending of this.pending.values())pending.reject(new Error('Codex stopped.'));this.pending.clear();
  }
}
