import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { workspacePath } from "../tools/pi/workspace-paths.mjs";

test("destructive tools reject roots, traversal, Git metadata and link escapes", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "gamesmith-paths-"));
  const root = join(fixture, "game");
  const outside = join(fixture, "outside");
  try {
    await mkdir(join(root, ".git"), { recursive: true });
    await mkdir(outside);
    await writeFile(join(outside, "keep.txt"), "keep");
    for (const path of [".", "subdir/..", "../outside", ".git", ".GIT/config"]) {
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
