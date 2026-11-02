import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { assembleHarnessRuntime } from "../tools/testing/assembled-runtime.mjs";
import { workspacePath } from "../tools/pi/workspace-paths.mjs";

test("Windows device names and trailing dots or spaces are rejected", async () => {
  if (process.platform !== "win32") return;
  const fixture = await mkdtemp(join(tmpdir(), "gamesmith-device-"));
  const root = join(fixture, "game");
  try {
    await mkdir(root);
    for (const path of ["CON", "nul.txt", "aux.gd", "sub/CON.gd", "dir./x.gd", "name /x.gd"]) {
      await assert.rejects(workspacePath(root, path, { destructive: true }), /device names/);
    }
    assert.equal(await workspacePath(root, "main.gd", { destructive: true }), join(root, "main.gd"));
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("destructive tools reject roots, traversal, Git metadata and link escapes", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "gamesmith-paths-"));
  const root = join(fixture, "game");
  const outside = join(fixture, "outside");
  try {
    await mkdir(join(root, ".git"), { recursive: true });
    await mkdir(outside);
    await writeFile(join(outside, "keep.txt"), "keep");
    for (const path of [".", "subdir/..", "../outside", ".git", ".GIT/config", "vendor/.git/config"]) {
      await assert.rejects(workspacePath(root, path, { destructive: true }));
    }
    await symlink(outside, join(root, "escape"), process.platform === "win32" ? "junction" : "dir");
    await symlink(root, join(root, "self"), process.platform === "win32" ? "junction" : "dir");
    await symlink(join(root, ".git"), join(root, "git-alias"), process.platform === "win32" ? "junction" : "dir");
    for (const path of ["escape", "escape/keep.txt", "escape/new/child.txt", "self", "git-alias/config"]) {
      await assert.rejects(workspacePath(root, path, { destructive: true }));
    }
    await assert.rejects(workspacePath(root, "escape/keep.txt"));
    assert.equal(await workspacePath(root, "."), root);
    assert.equal(await workspacePath(root, "new/child.txt", { destructive: true }), join(root, "new/child.txt"));
    assert.equal(await readFile(join(outside, "keep.txt"), "utf8"), "keep");
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

async function piTools(directory) {
  const runtime = join(directory, 'runtime');
  assembleHarnessRuntime('pi', runtime);
  const ai = join(runtime, 'node_modules/@earendil-works/pi-ai');
  await mkdir(ai, {recursive:true});
  await writeFile(join(ai, 'package.json'), JSON.stringify({type:'module', exports:'./index.mjs'}));
  await writeFile(join(ai, 'index.mjs'), 'export const Type=new Proxy({}, {get:()=>()=>({})});');
  const previous = process.env.GAMESMITH_MODEL_PROVIDER;
  process.env.GAMESMITH_MODEL_PROVIDER = 'openai_subscription';
  try {
    const registered = new Map();
    await (await import(pathToFileURL(join(runtime, 'gamesmith-extension.ts')))).default({
      on(){}, registerTool(tool){registered.set(tool.name, tool);},
    });
    return (name, args, cwd) => registered.get(name).execute('regression', args, undefined, undefined, {cwd});
  } finally {
    if (previous === undefined) delete process.env.GAMESMITH_MODEL_PROVIDER;
    else process.env.GAMESMITH_MODEL_PROVIDER = previous;
  }
}

test('assembled Pi move refuses existing files/directories and preserves both sides', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'gamesmith-pi-move-'));
  try {
    const execute = await piTools(fixture), root = join(fixture, 'game');
    await mkdir(join(root, 'occupied'), {recursive:true});
    await writeFile(join(root, 'source.txt'), 'source sentinel');
    await writeFile(join(root, 'destination.txt'), 'destination sentinel');
    for (const to of ['destination.txt', 'occupied', 'source.txt']) {
      await assert.rejects(execute('move_path', {from:'source.txt', to}, root), /Destination already exists/);
      assert.equal(await readFile(join(root, 'source.txt'), 'utf8'), 'source sentinel');
      assert.equal(await readFile(join(root, 'destination.txt'), 'utf8'), 'destination sentinel');
    }
    await execute('move_path', {from:'source.txt', to:'new/moved.txt'}, root);
    assert.equal(await readFile(join(root, 'new/moved.txt'), 'utf8'), 'source sentinel');
    await assert.rejects(access(join(root, 'source.txt')), {code:'ENOENT'});
  } finally { await rm(fixture, {recursive:true, force:true}); }
});

test('assembled Pi delete refuses nested Git metadata before deleting siblings and skips linked targets', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'gamesmith-pi-delete-'));
  try {
    const execute = await piTools(fixture), root = join(fixture, 'game');
    for (const name of ['.git', '.GIT']) {
      const containerName = name === '.git' ? 'vendor' : 'mixed';
      const container = join(root, containerName);
      await mkdir(join(container, 'nested', name), {recursive:true});
      await writeFile(join(container, 'ordinary.txt'), 'ordinary sentinel');
      await writeFile(join(container, 'nested', name, 'config'), 'metadata sentinel');
      await assert.rejects(execute('delete_path', {path:containerName}, root), /reserves .git metadata/);
      assert.equal(await readFile(join(container, 'ordinary.txt'), 'utf8'), 'ordinary sentinel');
      assert.equal(await readFile(join(container, 'nested', name, 'config'), 'utf8'), 'metadata sentinel');
    }
    await mkdir(join(root, 'worktree'));
    await writeFile(join(root, 'worktree/.git'), 'gitdir: elsewhere');
    await assert.rejects(execute('delete_path', {path:'worktree'}, root), /reserves .git metadata/);
    assert.equal(await readFile(join(root, 'worktree/.git'), 'utf8'), 'gitdir: elsewhere');
    const outside = join(fixture, 'outside');
    await mkdir(join(outside, '.git'), {recursive:true});
    await writeFile(join(outside, '.git/config'), 'outside sentinel');
    await mkdir(join(root, 'delete-me'));
    await symlink(outside, join(root, 'delete-me/escape'), process.platform==='win32'?'junction':'dir');
    await execute('delete_path', {path:'delete-me'}, root);
    assert.equal(await readFile(join(outside, '.git/config'), 'utf8'), 'outside sentinel');
    await assert.rejects(access(join(root, 'delete-me')), {code:'ENOENT'});
  } finally { await rm(fixture, {recursive:true, force:true}); }
});
