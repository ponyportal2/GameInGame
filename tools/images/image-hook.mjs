// AGY image jobs have no coding tools or MCP authority, even with global auto approval.
import {pathToFileURL} from 'node:url';
export function imagePermission(input) {
  const name=input.toolCall?.name;
  const args=input.toolCall?.args || {};
  const image=name==='generate_image';
  const subagents=args.Subagents;
  const delegate=name==='invoke_subagent' && Array.isArray(subagents) && subagents.length===1
    && subagents[0].TypeName==='image-generator' && !subagents[0].Workspace;
  return {decision:image || delegate || name==='finish'?'auto_approve':'deny',reason:'This disposable worker may only generate images.'};
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>text+=chunk);
  process.stdin.on('end',()=>{try{console.log(JSON.stringify(imagePermission(JSON.parse(text))))}catch{console.log(JSON.stringify({decision:'deny',reason:'Invalid image request.'}))}});
}
