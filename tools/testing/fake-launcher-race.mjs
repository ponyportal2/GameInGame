import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{windowsHide:true,stdio:'ignore'});
writeFileSync(process.argv[2],JSON.stringify({adapter:process.pid,child:child.pid}));
process.stdin.resume();
// Match the old worker: EOF exits the parent before a tree kill can find it.
process.stdin.on('end',()=>process.exit());
