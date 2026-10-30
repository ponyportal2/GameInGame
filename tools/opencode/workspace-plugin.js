import { dirname, isAbsolute, relative } from 'node:path';
import { realpath, writeFile } from 'node:fs/promises';
import { workspacePath } from './workspace-paths.mjs';

// OpenCode's native path permissions do not resolve Windows junctions. Keep
// native tools, but validate their actual filesystem targets before execution.
// Assembly names this server.ts, OpenCode v2's server-side plugin entrypoint;
// server.mjs remains the separate ACP transport module.
export default {
  id: 'gamesmith-workspace',
  async setup(ctx) {
    const directory = ctx.location.directory;
    await ctx.tool.hook('execute.before', async event => {
      if (!['read','write','edit','glob','grep'].includes(event.tool)) return;
      const value = event.input.path ?? '.';
      if (typeof value !== 'string') throw new Error('Permission denied: expected a workspace path.');
      const destructive = ['write','edit'].includes(event.tool);
      try {
        const target = await workspacePath(directory, isAbsolute(value) ? relative(directory,value) || '.' : value, {destructive});
        if (destructive) {
          const metadata = path => path.split(/[\\/]/).some(part => part.toLowerCase() === '.git');
          if (metadata(relative(directory,target))) throw new Error('GameSmith reserves .git metadata.');
          // A new file can sit below an alias to nested repository metadata.
          // Check the nearest existing ancestor as well as lexical segments.
          const root = await realpath(directory);
          for (let current = target;; current = dirname(current)) {
            let actual;
            try { actual = await realpath(current); }
            catch (error) { if (error.code !== 'ENOENT' || dirname(current) === current) throw error; continue; }
            if (metadata(relative(root,actual))) throw new Error('GameSmith reserves .git metadata.');
            break;
          }
        }
      } catch (error) { throw new Error('Permission denied: '+error.message); }
    });
    // OpenCode logs failed plugin loads and continues. The worker requires a
    // fresh acknowledgement from its own native child before admitting prompts.
    const guard = JSON.parse(process.env.GAMESMITH_OPENCODE_GUARD || 'null');
    if (guard) await writeFile(guard.path, JSON.stringify({token:guard.token,pid:process.pid,directory:await realpath(directory)}));
  },
};
