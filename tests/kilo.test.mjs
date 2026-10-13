import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OpenCodeServer,resolveExecutable} from '../tools/opencode/server.mjs';
import {buildConfig} from '../tools/opencode/protocol.mjs';

test('Kilo npm resolver selects Kilo rather than OpenCode',()=>{
 const root=mkdtempSync(join(tmpdir(),'gs-kilo-resolver-'));
 const shim=join(root,'kilo.cmd'),entry=join(root,'node_modules/@kilocode/cli/bin/kilo');
 mkdirSync(join(root,'node_modules/@kilocode/cli/bin'),{recursive:true});writeFileSync(shim,'fixture');writeFileSync(entry,'fixture');
 assert.deepEqual(resolveExecutable(shim,'win32','kilo'),{bin:process.execPath,prefix:[entry]});
 assert.throws(()=>resolveExecutable(shim,'win32','opencode'),/OpenCode/);
});

test('Kilo exposes only workspace and GameSmith tools without overriding native models',()=>{
 const config=buildConfig({harness:'kilo',plugin:'C:/gamesmith/plugin.mjs',mcp:'C:/gamesmith/mcp.mjs',prompt_path:'C:/gamesmith/prompt.md'});
 assert.equal(config.permission['*'],'deny');
 assert.equal(config.permission.bash,'deny');
 assert.equal(config.permission.apply_patch,'allow');
 assert.equal(config.permission.gamesmith_undefined,undefined);
 assert.equal(config.permission['gamesmith_*'],'allow');
 for(const name of ['model','small_model','provider','compaction']) assert.equal(config[name],undefined);
});
test('Kilo transport uses authenticated Kilo directory routing',()=>{
 const server=new OpenCodeServer({workspace:'C:/game',harness:'kilo'});
 assert.equal(server.harness,'kilo');assert.equal(server.label,'Kilo');
 assert.equal(server.prefix,'KILO');assert.equal(server.directoryHeader,'x-kilo-directory');
});
