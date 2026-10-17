import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {workspacePath} from './workspace-paths.mjs';

export async function rgSearch(args,{workspace,callHost,signal}) {
    signal?.throwIfAborted();
    const {target,pattern}=args;
    if(!['source','runtime'].includes(target) || typeof pattern!=='string' || !pattern || pattern.length>1024)
      return {ok:false,error:'Expected source/runtime target and a regex pattern of 1..1024 characters.'};
    const offset=args.offset??0,limit=args.limit??100;
    if(!Number.isInteger(offset)||offset<0||offset>10000||!Number.isInteger(limit)||limit<1||limit>100 || args.case_sensitive!==undefined && typeof args.case_sensitive!=='boolean')
      return {ok:false,error:'Expected offset 0..10000, limit 1..100 and optional case_sensitive boolean.'};
    let inspection,input;
    const flags=['--no-config','--json','--color','never','--line-number'];
    if(args.case_sensitive===false)flags.push('--ignore-case');
    if(target==='source') {
      const path=await workspacePath(workspace,args.path||'.');
      // rg does not follow symlinks/junctions; explicit roots are validated above.
      flags.push('--sort','path','--max-columns','4096','--max-columns-preview','--glob','!.git/**','--glob','!.godot/**');
      if(args.glob!==undefined) {if(typeof args.glob!=='string'||args.glob.length>1024)return {ok:false,error:'Expected a bounded glob.'};flags.push('--glob',args.glob);}
      flags.push('--regexp',pattern,'--',path);
    } else {
      const query={discover_properties:false,limit:100,offset:args.runtime_offset??0};
      for(const key of ['root','depth','class','script','group','properties'])if(args[key]!==undefined)query[key]=args[key];
      inspection=await callHost('inspect_runtime',query,signal);
      if(!inspection.ok)return inspection;
      input=inspection.nodes.map(node=>JSON.stringify(node)).join('\n')+'\n';
      flags.push('--regexp',pattern,'--','-');
    }
    signal?.throwIfAborted();
    return await new Promise((resolve,reject)=>{
      const child=spawn('rg',flags,{cwd:workspace,windowsHide:true,stdio:['pipe','pipe','pipe']});
      const rows=[];let matched=0,hasMore=false,stderr='',settled=false,parseError;
      const abort=()=>child.kill();
      const finish=(error,result)=>{if(settled)return;settled=true;signal?.removeEventListener('abort',abort);error?reject(error):resolve(result);};
      signal?.addEventListener('abort',abort,{once:true});
      if(signal?.aborted)abort();
      child.on('error',error=>finish(null,{ok:false,error:error.code==='ENOENT'?'System rg is not installed or not on PATH.':error.message}));
      child.stdin.on('error',()=>{}); // rg can exit early after reaching the page limit.
      child.stderr.on('data',data=>{if(stderr.length<2048)stderr+=data.toString().slice(0,2048-stderr.length);});
      const lines=createInterface({input:child.stdout});
      lines.on('line',line=>{
        let record;try{record=JSON.parse(line);}catch{return;}
        if(record.type!=='match')return;
        if(++matched<=offset)return;
        if(rows.length>=limit){hasMore=true;child.kill();return;}
        const data=record.data;
        const decode=value=>value.text??Buffer.from(value.bytes||'','base64').toString('utf8');
        if(target==='runtime') {try{rows.push(JSON.parse(decode(data.lines)));}catch{parseError='Invalid runtime record returned by rg.';child.kill();}}
        else {
          const root=workspace.replaceAll('\\','/').replace(/\/$/,'')+'/';
          const path=decode(data.path).replaceAll('\\','/');
          rows.push({path:path.startsWith(root)?path.slice(root.length):path,line:data.line_number,text:decode(data.lines).replace(/\r?\n$/,'')});
        }
      });
      child.on('close',code=>{
        lines.close();
        if(signal?.aborted){finish(signal.reason||new Error('Search aborted.'));return;}
        if(parseError){finish(null,{ok:false,error:parseError});return;}
        if(code!==0&&code!==1&&!hasMore){finish(null,{ok:false,error:stderr||'rg search failed.'});return;}
        finish(null,{ok:true,[target==='runtime'?'nodes':'matches']:rows,has_more:hasMore,next_offset:hasMore?offset+rows.length:null,
          ...(inspection?{game_generation:inspection.game_generation,runtime_next_offset:inspection.next_offset,runtime_truncated_by:inspection.truncated_by}:{}),engine:'system_rg'});
      });
      child.stdin.end(input);
    });
}
