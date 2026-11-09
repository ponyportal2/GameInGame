import {spawn,spawnSync} from 'node:child_process';
import {existsSync,readFileSync,mkdirSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {killProcessTree} from './process-tree.mjs';
import {toolSpecs} from './workspace-tools.mjs';

export function resolveExecutable(bin=process.env.GAMESMITH_CLAUDE_BIN || 'claude',platform=process.platform){
  if(/\.(mjs|js)$/i.test(bin) && existsSync(bin))return {bin:process.execPath,prefix:[resolve(bin)]};
  if(platform!=='win32')return {bin,prefix:[]};
  const found=existsSync(bin)?resolve(bin):spawnSync('where.exe',[bin],{encoding:'utf8',windowsHide:true}).stdout?.trim().split(/\r?\n/).find(p=>/\.(exe|cmd|ps1)$/i.test(p));
  if(!found)throw new Error('Claude Code CLI was not found. Install Claude Code or set GAMESMITH_CLAUDE_BIN.');
  if(/\.exe$/i.test(found))return {bin:found,prefix:[]};
  const entry=join(dirname(found),'node_modules/@anthropic-ai/claude-code/cli.js');
  if(!existsSync(entry))throw new Error('Could not resolve Claude Code. Set GAMESMITH_CLAUDE_BIN to its executable.');
  return {bin:process.execPath,prefix:[entry]};
}
export function launchArgs(config){
  const args=['--print','--verbose','--output-format','stream-json','--input-format','stream-json','--include-partial-messages','--replay-user-messages',
    '--tools','','--allowedTools',toolSpecs().map(t=>'mcp__gamesmith__'+t.name.slice(10)).join(','),
    '--strict-mcp-config','--mcp-config',JSON.stringify({mcpServers:{gamesmith:{command:process.execPath,args:[config.mcp,config.config_path]}}}),
    '--permission-mode','default','--permission-prompts','none','--setting-sources','user',
    // Preserve native auth/model settings; broad isolation modes also remove MCP or user model selection.
    '--settings',JSON.stringify({disableAllHooks:true,autoMemoryEnabled:false,agent:'',env:{CLAUDE_CODE_DISABLE_CLAUDE_MDS:'1'}}),
    '--disable-slash-commands','--system-prompt-snapshot','off','--append-system-prompt',readFileSync(config.prompt_path,'utf8')];
  if(config.session)args.push('--resume',config.session);
  return args;
}
export class ClaudeServer{
  constructor(config,{onRecord,onExit,onStderr}){Object.assign(this,{config,onRecord,onExit,onStderr});}
  get pid(){return this.child?.pid;}
  start(){
    const exe=resolveExecutable(),cwd=join(dirname(this.config.session_file),'native-workspace');mkdirSync(cwd,{recursive:true});
    this.child=spawn(exe.bin,[...exe.prefix,...launchArgs(this.config)],{cwd,env:{...process.env},windowsHide:true,stdio:['pipe','pipe','pipe']});
    this.child.stdin.on('error',()=>{});
    const fail=error=>{if(!this.closing){this.closing=true;this.onExit(error);}};
    this.child.once('error',fail);this.child.once('exit',code=>fail(new Error('Claude Code exited with code '+code+'.')));
    createInterface({input:this.child.stderr}).on('line',this.onStderr);
    createInterface({input:this.child.stdout}).on('line',line=>{try{this.onRecord(JSON.parse(line));}catch(error){fail(new Error('Invalid Claude Code stream: '+error.message));}});
  }
  send(record){if(!this.child?.stdin.writable)throw new Error('Claude Code is unavailable.');this.child.stdin.write(JSON.stringify(record)+'\n');}
  close(){this.closing=true;if(this.pid && this.child.exitCode===null)killProcessTree(this.pid);}
}
