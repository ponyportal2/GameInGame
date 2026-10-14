import {writeFileSync,renameSync} from 'node:fs';

// OMP's extensions differ from Pi's. Keep this extension limited to tool policy;
// tools execute in GameSmith's existing bounded workspace/host implementation.
export default function (omp) {
  const config=JSON.parse(process.env.GAMESMITH_OMP_POLICY || '{}');
  if(!config.nonce || !config.path || !Array.isArray(config.tools))throw new Error('Missing GameSmith OMP policy.');
  const allowed=new Set(config.tools);
  async function activate(){
    await omp.setActiveTools([...allowed]);
    const actual=[...omp.getActiveTools()].sort();
    if(JSON.stringify(actual)!==JSON.stringify([...allowed].sort()))throw new Error('OMP active tool policy did not match GameSmith.');
    return actual;
  }
  omp.on('before_agent_start',async()=>{await activate();});
  omp.on('tool_call',event=>{
    try{if(!allowed.has(event.toolName))return {block:true,reason:'Only GameSmith host tools are available.'};}
    catch(error){return {block:true,reason:'GameSmith tool policy failed: '+String(error)};}
  });
  omp.registerCommand('gamesmith-ready',{description:'Private GameSmith policy readiness check',handler:async()=>{
    const tools=await activate();
    writeFileSync(config.path+'.tmp',JSON.stringify({nonce:config.nonce,tools}));renameSync(config.path+'.tmp',config.path);
  }});
}
