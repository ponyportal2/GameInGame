import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {permissionDecision} from './protocol.mjs';
let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>input+=chunk);
process.stdin.on('end',()=>{
  try {
    const config=JSON.parse(readFileSync(process.argv[2],'utf8'));
    const state=JSON.parse(readFileSync(join(config.bridge_dir,'operation.json'),'utf8'));
    console.log(JSON.stringify(permissionDecision(JSON.parse(input),state)));
  }catch{console.log(JSON.stringify({decision:'deny',reason:'GameSmith permission state is unavailable.'}));}
});
