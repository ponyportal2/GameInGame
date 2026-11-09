// Opt-in investigation, not an isolation acceptance gate. Uses installed CLIs,
// isolated homes, synthetic credentials and a loopback metadata service. No
// inference response is supplied and no real provider credentials are copied.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:http';
import {createInterface} from 'node:readline';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {assembleHarnessRuntime} from './assembled-runtime.mjs';
import {killProcessTree} from '../agent/process-tree.mjs';

const self=fileURLToPath(import.meta.url), sleep=ms=>new Promise(r=>setTimeout(r,ms));
if(process.argv[2]==='--child') {
  const {harness, mode, config}=JSON.parse(readFileSync(process.argv[3],'utf8'));
  const module=await import(pathToFileURL(join(config.directory,'server.mjs')));
  const Type=module[harness==='cursor'?'CursorServer':'GrokBuildServer'];
  let server, child, serial=0, records=[], errors='';
  const pending=new Map();
  const until=async predicate=>{for(let i=0;i<150;i++){if(predicate())return;await sleep(20);}};
  try {
    if(mode==='adapter') {
      server=new Type(config,{onStderr:s=>errors+=s+'\n'});
      await server.start();
      await server.request('session/new',server.sessionParams());
    } else if(mode==='image') {
      server=new Type({...config,image_job:true},{onStderr:s=>errors+=s+'\n'});
      await server.start();
      // The metadata fixture deliberately cannot complete image generation.
      // Observe hook execution, then stop only this owned process tree.
      server.generateImage('Customization probe; no image is required.').catch(()=>{});
      await until(()=>existsSync(config.hook_marker));
    } else {
      const exe=module.resolveExecutable();
      const args=harness==='cursor'?['acp']:['--tools','use_tool,search_tool','--no-subagents','--disable-web-search','--permission-mode','default','agent','--no-leader','stdio'];
      child=spawn(exe.bin,[...exe.prefix,...args],{cwd:config.cwd,env:process.env,windowsHide:true,stdio:['pipe','pipe','pipe']});
      child.stderr.on('data',d=>errors+=d);
      createInterface({input:child.stdout}).on('line',line=>{
        let r;try{r=JSON.parse(line);}catch{return;}
        records.push(r);
        if(pending.has(r.id)){const {resolve,reject}=pending.get(r.id);pending.delete(r.id);r.error?reject(new Error(JSON.stringify(r.error))):resolve(r.result);}
        else if(r.id)child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:r.id,result:{outcome:{outcome:'cancelled'}}})+'\n');
      });
      const request=(method,params)=>new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});child.stdin.write(JSON.stringify({jsonrpc:'2.0',id,method,params})+'\n');});
      await request('initialize',{protocolVersion:1,clientCapabilities:{}});
      await request('authenticate',{methodId:harness==='cursor'?'cursor_login':'cached_token'});
      await request('session/new',{cwd:config.cwd,mcpServers:[]});
    }
    await until(()=>existsSync(config.hook_marker)&&existsSync(config.mcp_marker)) ;
    console.log(JSON.stringify({harness,mode,hook_executed:existsSync(config.hook_marker),global_mcp_started:existsSync(config.mcp_marker),explicit_mcp_started:existsSync(config.explicit_marker)}));
  } catch(error) { console.log(JSON.stringify({harness,mode,error:error.message,hook_executed:existsSync(config.hook_marker),global_mcp_started:existsSync(config.mcp_marker),explicit_mcp_started:existsSync(config.explicit_marker)})); }
  finally {
    server?.close();if(child?.exitCode===null)killProcessTree(child.pid);
    writeFileSync(join(config.directory,mode+'.stderr'),errors);
    writeFileSync(join(config.directory,mode+'.records.json'),JSON.stringify(records));
  }
} else {
  assert.equal(process.platform,'win32','This installed-CLI reproducer currently targets Windows');
  const root=mkdtempSync(join(tmpdir(),'gs-native-customization-'));
  console.log('Artifacts: '+root);
  const field=(n,v)=>Buffer.concat([Buffer.from([n*8+2,v.length]),v]);
  const requests=[];
  const http=createServer(async(req,res)=>{
    for await(const chunk of req){} // Never persist request headers/credentials.
    requests.push(req.url);
    const model=Buffer.concat([field(1,Buffer.from('default[]')),field(4,Buffer.from('Auto'))]);
    const data=req.url.includes('GetUsableModels')||req.url.includes('GetDefaultModelForCli')?field(1,model):req.url.includes('AvailableModels')?field(2,Buffer.concat([field(1,Buffer.from('default[]')),Buffer.from([16,1,40,1])])):Buffer.alloc(0);
    res.setHeader('content-type','application/proto');res.end(data);
  });
  await new Promise(resolve=>http.listen(0,'127.0.0.1',resolve));
  const results=[];
  try {
    for(const harness of ['grok-build','cursor']) {
      const template=assembleHarnessRuntime(harness,join(root,harness,'assembled'));
      const module=await import(pathToFileURL(join(template,'server.mjs')));
      const exe=module.resolveExecutable();
      const version=spawnSync(exe.bin,[...exe.prefix,'--version'],{encoding:'utf8',windowsHide:true,timeout:15000});
      assert.equal(version.status,0,'Installed '+harness+' version probe');
      console.log(harness+': '+version.stdout.trim());
      for(const mode of harness==='cursor'?['control','adapter','image']:['control','adapter']) {
        const directory=join(root,harness,mode), home=join(directory,'home'), appdata=join(directory,'appdata');
        for(const p of [directory,home,appdata,join(home,'.grok/hooks'),join(home,'.cursor'),join(appdata,'Cursor')])mkdirSync(p,{recursive:true});
        assembleHarnessRuntime(harness,directory);
        const config={directory,cwd:join(directory,'native-workspace'),workspace:join(directory,'game'),session_file:join(directory,'session.json'),config_path:join(directory,'runtime.json'),mcp:join(directory,'probe-mcp.mjs'),hook_marker:join(directory,'personal-hook-ran'),mcp_marker:join(directory,'personal-mcp-started'),explicit_marker:join(directory,'explicit-mcp-started')};
        for(const p of [config.cwd,config.workspace])mkdirSync(p,{recursive:true});
        const hook=join(directory,'personal-hook.mjs');
        writeFileSync(hook,`import {appendFileSync} from 'node:fs';appendFileSync(${JSON.stringify(config.hook_marker)},'ran\\n');console.log('{}');`);
        const command=`"${process.execPath}" "${hook}"`;
        const hookFile=harness==='cursor'?join(home,'.cursor/hooks.json'):join(home,'.grok/hooks/probe.json');
        const hooks=harness==='cursor'?{version:1,hooks:{sessionStart:[{command}],beforeSubmitPrompt:[{command}]}}:{hooks:{SessionStart:[{hooks:[{type:'command',command,timeout:5}]}]}};
        writeFileSync(hookFile,JSON.stringify(hooks));
        // A harmless MCP process proves startup separately from tool invocation.
        writeFileSync(config.mcp,`import {writeFileSync} from 'node:fs';import {createInterface} from 'node:readline';writeFileSync(process.argv[2], 'started');createInterface({input:process.stdin}).on('line',line=>{let r;try{r=JSON.parse(line);}catch{return;}if(r.id===undefined)return;const result=r.method==='initialize'?{protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'customization-probe',version:'1'}}:r.method==='tools/list'?{tools:[]}:{prompts:[],resources:[]};console.log(JSON.stringify({jsonrpc:'2.0',id:r.id,result}));});`);
        // Production supplies config_path as the MCP's first argument.
        config.config_path=config.explicit_marker;
        const registry={mcpServers:{personal:{command:process.execPath,args:[config.mcp,config.mcp_marker]}}};
        if(harness==='cursor')writeFileSync(join(home,'.cursor/mcp.json'),JSON.stringify(registry));
        else writeFileSync(join(home,'.grok/config.toml'),`[mcp_servers.personal]\ncommand = ${JSON.stringify(process.execPath)}\nargs = [${JSON.stringify(config.mcp)}, ${JSON.stringify(config.mcp_marker)}]\n`);
        const jwt='eyJhbGciOiJub25lIn0.'+Buffer.from(JSON.stringify({sub:'native-probe',exp:4102444800})).toString('base64url')+'.probe';
        writeFileSync(join(appdata,'Cursor/auth.json'),JSON.stringify({accessToken:jwt,refreshToken:'native-probe'}));
        const env={...process.env,HOME:home,USERPROFILE:home,APPDATA:appdata,XDG_CONFIG_HOME:join(home,'.config'),GROK_HOME:join(home,'.grok'),CURSOR_CONFIG_DIR:join(home,'.cursor'),CURSOR_DATA_DIR:join(home,'.cursor'),CURSOR_API_ENDPOINT:'http://127.0.0.1:'+http.address().port,XAI_API_KEY:'native-probe',GROK_DISABLE_AUTOUPDATER:'1'};
        for(const key of ['CURSOR_API_KEY','CURSOR_AUTH_TOKEN','GROK_CONFIG','GROK_CONFIG_PATH','GROK_AUTH_PATH'])delete env[key];
        env[harness==='cursor'?'GAMESMITH_CURSOR_BIN':'GAMESMITH_GROK_BUILD_BIN']=harness==='cursor'?exe.prefix[0]:exe.bin;
        const request=join(directory,'probe.json');writeFileSync(request,JSON.stringify({harness,mode,config}));
        const child=spawn(process.execPath,[self,'--child',request],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
        let stdout='',stderr='';child.stdout.on('data',d=>stdout+=d);child.stderr.on('data',d=>stderr+=d);
        const timeout=setTimeout(()=>killProcessTree(child.pid),20000);
        const code=await new Promise(resolve=>child.once('exit',resolve));clearTimeout(timeout);
        writeFileSync(join(directory,'probe.stdout'),stdout);writeFileSync(join(directory,'probe.stderr'),stderr);
        assert.equal(code,0,harness+' '+mode+' completed: '+stdout+' '+stderr);
        const result=JSON.parse(stdout.trim().split('\n').at(-1));results.push(result);console.log(JSON.stringify(result));
        assert.equal(readFileSync(hookFile,'utf8'),JSON.stringify(hooks),'Probe never rewrites personal hook configuration');
      }
    }
    writeFileSync(join(root,'results.json'),JSON.stringify({results,metadata_paths:requests},null,2));
    const grok=results.find(r=>r.harness==='grok-build'&&r.mode==='control');
    assert(grok.hook_executed&&grok.global_mcp_started,'Native Grok hook and MCP positive controls');
    const cursor=results.find(r=>r.harness==='cursor'&&r.mode==='adapter');
    assert(!cursor.error&&cursor.global_mcp_started&&cursor.explicit_mcp_started,'Assembled Cursor server starts personal and explicit probe MCPs');
    assert(results.find(r=>r.harness==='cursor'&&r.mode==='image').hook_executed,'Cursor image launch reproduces personal hook execution');
    console.log('Reproduction completed. This demonstrates inherited customization, NOT isolation or model/auth acceptance.');
  } finally {http.closeAllConnections();http.close();}
}
