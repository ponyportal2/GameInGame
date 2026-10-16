import {spawn,spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {join,dirname,resolve} from 'node:path';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';
export function resolveExecutable(bin=process.env.GAMESMITH_AGY_BIN || '',platform=process.platform) {
  if(!bin){const standard=join(process.env.LOCALAPPDATA || '', 'agy','bin','agy.exe');bin=platform==='win32' && existsSync(standard)?standard:'agy';}
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.exe$/i.test(p));
  if(!found)throw new Error('AGY CLI was not found. Install Antigravity CLI or set GAMESMITH_AGY_BIN to agy.exe.');
  return {bin:found,prefix:[]};
}
export class AgyServer {
  constructor(config,{onRecord=()=>{},onExit=()=>{},onStderr=()=>{}}={}){Object.assign(this,{config,onRecord,onExit,onStderr});}
  get pid(){return this.child?.pid;}
  async start() {
    const exe=resolveExecutable(),directory=dirname(this.config.session_file);
    this.cwd=join(directory,'native-workspace');mkdirSync(join(this.cwd,'.agents','agents'),{recursive:true});
    const hook=join(directory,this.config.image_job?'image-hook.mjs':'hook.mjs');
    const command=[process.execPath,hook,this.config.config_path].map(s=>'"'+s.replaceAll('"','\\"')+'"').join(' ');
    writeFileSync(join(this.cwd,'.agents','hooks.json'),JSON.stringify({'gamesmith-policy':{
      PreToolUse:[{matcher:'*',hooks:[{type:'command',command,timeout:10}]}]
    }}));
    const front={name:'gamesmith',description:this.config.image_job?'Isolated image generation':'GameSmith game editing',mainAgent:true,subagent:false,
      inheritCustomizations:false,inheritMcp:false,hooks:['gamesmith-policy'],
      mcpServers:this.config.image_job?[]:[{name:'gamesmith',command:process.execPath,args:[this.config.mcp,this.config.config_path]}]};
    writeFileSync(join(this.cwd,'.agents','agents','gamesmith.md'),'---\n'+Object.entries(front).map(([k,v])=>k+': '+JSON.stringify(v)).join('\n')+'\n---\n'+readFileSync(this.config.prompt_path,'utf8'));
    const args=[...exe.prefix,'--agent','gamesmith','--disable-slash-commands','--input-format','stream-json','--output-format','stream-json'];
    if(this.config.session)args.push('--conversation',this.config.session);
    this.child=spawn(exe.bin,args,{cwd:this.cwd,windowsHide:true,stdio:['pipe','pipe','pipe']});
    this.child.stdin.on('error',()=>{});
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{
      let record;try{record=JSON.parse(line);}catch{this.onStderr(line);return;}
      this.onRecord(record);
    });
    this.child.once('exit',code=>{if(!this.closing)this.onExit(new Error(`AGY exited with code ${code}.`));});
    await new Promise((resolve,reject)=>{this.child.once('spawn',resolve);this.child.once('error',error=>{if(!this.closing)this.onExit(error);reject(error);});});
  }
  prompt(message) {
    if(!this.child?.stdin.writable || this.closing)throw new Error('AGY is unavailable.');
    this.child.stdin.write(JSON.stringify({event:'user',message:{content:message}})+'\n');
  }
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);}
}
