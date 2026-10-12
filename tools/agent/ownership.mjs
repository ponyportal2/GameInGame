// Kernel-held ownership; process/pipe closure releases it without lease expiry.
import net from 'node:net';
import { createHash } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
let workspace=resolve(process.argv[2]);
try {workspace=realpathSync(workspace);} catch {workspace=resolve(realpathSync(dirname(workspace)),basename(workspace));}
if(process.platform==='win32') workspace=workspace.toLowerCase();
const key=createHash('sha256').update(workspace).digest('hex');
const endpoint=process.platform==='win32' ? '\\\\.\\pipe\\gamesmith-editor-'+key : '\0gamesmith-editor-'+key;
const server=net.createServer(socket=>socket.end());
server.once('error',error=>{console.log(JSON.stringify({ok:false,error:error.code==='EADDRINUSE' ? 'This game is currently owned by another GameSmith window. Close that game in the other window before editing.' : 'Could not reserve game ownership: '+error.message}));process.exit(1);});
server.listen(endpoint,()=>console.log(JSON.stringify({ok:true})));
process.stdin.resume();
process.stdin.on('end',()=>{server.close();process.exit();});
