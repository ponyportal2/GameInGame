import { isAbsolute, relative } from 'node:path';
import { workspacePath } from './workspace-paths.mjs';
import { hostTools } from './host-tools.mjs';

// Native hooks enforce the same cooperative workspace policy as the other adapters.
export default async function ({directory}) {
  const native = ['read','write','edit','apply_patch','glob','grep','list'];
  const host = Object.keys(hostTools).map(name=>'gamesmith_'+name);
  return {
    'tool.execute.before': async (input, output) => {
      if (![...native,...host].includes(input.tool)) throw new Error('This tool is unavailable inside GameSmith.');
      const args = output.args || {};
      const destructive = ['write','edit','apply_patch','gamesmith_delete_path','gamesmith_move_path'].includes(input.tool);
      const fileTool = native.includes(input.tool) || ['gamesmith_git_diff','gamesmith_delete_path','gamesmith_move_path'].includes(input.tool);
      for (const key of fileTool ? ['filePath','path','from','to'] : []) if (typeof args[key] === 'string') {
        const value = isAbsolute(args[key]) ? relative(directory,args[key]) || '.' : args[key];
        await workspacePath(directory,value,{destructive});
      }
      if (input.tool === 'apply_patch') {
        const paths=[...String(args.patchText || '').matchAll(/^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)\r?$/gm)].map(match=>match[1].trim());
        if (!paths.length) throw new Error('Expected file paths in the patch.');
        for (const path of paths) await workspacePath(directory,isAbsolute(path) ? relative(directory,path) : path,{destructive:true});
      }
    },
  };
}
