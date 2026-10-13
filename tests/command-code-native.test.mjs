// Opt-in: real supported CLI against a local provider, never the player's model.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {TOOL_NAMES} from '../tools/command-code/policy.mjs';

test('native ACP provider boundary, persistent history, compaction and guard failures', {skip:!process.env.GAMESMITH_TEST_COMMAND_CODE_BIN,timeout:180000}, async t=>{
 const root=mkdtempSync(join(tmpdir(),'gs-native-command-')),home=join(root,'home'),workspace=join(root,'workspace');
 mkdirSync(join(home,'.commandcode'),{recursive:true});mkdirSync(workspace);mkdirSync(join(root,'bridge'));
 const requests=[];let nextTool,failSummary=false,reportedTokens=65000;
 const http=createServer(async(req,res)=>{
   let raw='';for await(const b of req)raw+=b;const body=JSON.parse(raw);requests.push(body);
   const tool=nextTool;nextTool=undefined;
   const summary=!(body.tools?.length);
   const message=tool?{role:'assistant',content:null,tool_calls:[{id:'call-'+requests.length,type:'function',function:{name:tool.name,arguments:JSON.stringify(tool.input)}}]}:{role:'assistant',content:summary?'Summary preserves first ordinary turn and GameSmith policy.':'NATIVE_BOUNDARY_OK '+ 'summary '.repeat(4000)};
   if(failSummary && (!body.tools || body.tools.length===0)){res.writeHead(400);res.end(JSON.stringify({error:{message:'Deliberate summary failure'}}));return;}
   res.writeHead(200,{'Content-Type':'text/event-stream'});
   res.end('data: '+JSON.stringify({id:'response',object:'chat.completion.chunk',choices:[{index:0,delta:message,finish_reason:tool?'tool_calls':'stop'}],usage:{prompt_tokens:summary?1000:reportedTokens,completion_tokens:100,total_tokens:(summary?1000:reportedTokens)+100}})+'\n\ndata: [DONE]\n\n');
 });
 await new Promise(r=>http.listen(0,'127.0.0.1',r));t.after(()=>{http.closeAllConnections();http.close();});
 writeFileSync(join(home,'.commandcode','settings.json'),JSON.stringify({model:'fixture/policy',disableScratchpad:true,compactMode:'fast'}));
 writeFileSync(join(home,'.commandcode','auth.json'),JSON.stringify({apiKey:'fixture-only'}));
 writeFileSync(join(home,'.commandcode','providers.json'),JSON.stringify({provider:{fixture:{api:'openai-completions',baseURL:'http://127.0.0.1:'+http.address().port+'/v1',apiKey:false,models:{policy:{contextWindow:100000,maxOutput:4096}}}}}));
 const mod=join(root,'gamesmith.ts');copyFileSync('tools/command-code/gamesmith.ts',mod);copyFileSync('tools/pi/workspace-paths.mjs',join(root,'workspace-paths.mjs'));copyFileSync('tools/command-code/policy.mjs',join(root,'policy.mjs'));
 writeFileSync(join(root,'prompt.md'),'GAMESMITH_NATIVE_POLICY_MARKER');
 let child,records=[],pending=new Map(),serial=0,errors='';
 const start=()=>{
   const saved=existsSync(join(root,'session.json'))?JSON.parse(readFileSync(join(root,'session.json'))):{};
   writeFileSync(join(root,'config.json'),JSON.stringify({workspace,mod,bridge_dir:join(root,'bridge'),prompt_path:join(root,'prompt.md'),session_file:join(root,'session.json'),session_id:saved.session}));
   child=spawn(process.execPath,['tools/command-code/worker.mjs',join(root,'config.json')],{env:{...process.env,HOME:home,USERPROFILE:home,CMD_LOCAL_ONLY:'1',COMMANDCODE_API_KEY:'fixture-only',GAMESMITH_COMMAND_CODE_BIN:process.env.GAMESMITH_TEST_COMMAND_CODE_BIN},stdio:['pipe','pipe','pipe']});
   child.stderr.on('data',b=>errors+=b);createInterface({input:child.stdout}).on('line',line=>{const r=JSON.parse(line);records.push(r);if(r.type==='response'){pending.get(r.id)?.(r);pending.delete(r.id);}});
 };
 t.after(()=>child?.stdin.end());
 const command=(type,message)=>new Promise(r=>{const id=String(++serial);pending.set(id,r);child.stdin.write(JSON.stringify({id,type,message})+'\n');});
 const prompt=async message=>{records=[];const r=await command('prompt',message);assert.equal(r.success,true,JSON.stringify(r)+' '+errors);for(let i=0;i<1000;i++){const c=records.find(r=>r.type==='complete');if(c)return c;await new Promise(r=>setTimeout(r,10));}throw new Error('No native completion '+errors);};
 // Native 1.82.1 leaves a disabled-tool catalog in its prompt. We accept that
 // documented limitation; schemas and execution must still enforce our policy.
 const assertBoundary=()=>{for(const r of requests){assert.equal(r.model,'policy','native configured model remains inherited');const names=(r.tools || []).map(t=>t.function.name);assert.ok(names.every(n=>TOOL_NAMES.includes(n)),JSON.stringify(names));if(names.length){assert.deepEqual([...names].sort(),[...TOOL_NAMES].sort());assert.ok(JSON.stringify(r.messages).includes('GAMESMITH_NATIVE_POLICY_MARKER'));}}};
 start();assert.equal((await prompt('first ordinary turn')).ok,true);assert.ok(requests.length>0);assertBoundary();
 const id=JSON.parse(readFileSync(join(root,'session.json'))).session;
 assert.equal((await prompt('second ordinary turn')).ok,true);assertBoundary();
 // A model can hallucinate a catalog-only tool. It must still be denied.
 nextTool={name:'shell_command',input:{command:'echo forbidden > "'+join(workspace,'forbidden.txt')+'"'}};
 await prompt('attempt disabled catalog tool');
 assert.equal(existsSync(join(workspace,'forbidden.txt')),false,'disabled shell must not execute');
 assert.ok(requests.at(-1).messages.some(m=>m.role==='tool' && /not allowed|disabled|unavailable|not found|unknown|no tool named/i.test(JSON.stringify(m))), 'native response must report the forbidden tool denial: '+JSON.stringify(requests.at(-1).messages.filter(m=>m.role==='tool')));
 assertBoundary();
 for(let i=0;i<6;i++)assert.equal((await prompt('seed history '+i)).ok,true);
 const compact=await command('compact');assert.equal(compact.data.ok,true,JSON.stringify(compact));assert.equal(compact.data.no_op,false);
 assert.equal((await prompt('ordinary after compact')).ok,true);assertBoundary();
 for(let i=0;i<4;i++)assert.equal((await prompt('seed failed summary '+i)).ok,true);
 failSummary=true;
 const failed=await command('compact');assert.equal(failed.success,false,JSON.stringify(failed));
 failSummary=false;
 assert.equal((await prompt('ordinary after failed compact')).ok,true);assertBoundary();
 const summariesBefore=requests.filter(r=>!r.tools?.length).length;
 reportedTokens=95000;
 for(let i=0;i<8;i++)assert.equal((await prompt('seed native automatic compact '+i)).ok,true);
 reportedTokens=65000;
 assert.ok(requests.filter(r=>!r.tools?.length).length>summariesBefore,'native automatic compaction reaches the provider');
 assert.equal((await prompt('ordinary after native automatic compact')).ok,true);assertBoundary();
 nextTool={name:'write_file',input:{file_path:join(root,'escape.txt'),content:'must never exist'}};
 await prompt('path rejection');assert.equal(existsSync(join(root,'escape.txt')),false);assertBoundary();
 // Fault-inject the validator used by the production hook. Native hook exceptions
 // are fail-open in 1.82.1, so our complete hook must catch unexpected failures.
 writeFileSync(join(root,'workspace-paths.mjs'),`import {workspacePath as real} from ${JSON.stringify(pathToFileURL(resolve('tools/pi/workspace-paths.mjs')).href)}; export async function workspacePath(root,path,options){if(path.endsWith('throw.txt'))throw new Error('DELIBERATE_VALIDATOR_CRASH'); return real(root,path,options);}`);
 await command('cancel');child.stdin.end();await new Promise(r=>child.once('close',r));start();
 assert.equal((await prompt('after explicit load')).ok,true);assertBoundary();assert.equal(JSON.parse(readFileSync(join(root,'session.json'))).session,id);
 assert.ok(requests.at(-1).messages.some(m=>JSON.stringify(m).includes('first ordinary turn')),'native history survives restart');
 nextTool={name:'write_file',input:{file_path:join(workspace,'throw.txt'),content:'must never exist'}};
 await prompt('unexpected hook throw');assert.equal(existsSync(join(workspace,'throw.txt')),false,'throw must prevent execution');assertBoundary();
 console.log('Native boundary requests verified: '+requests.length+'; session '+id);
});
