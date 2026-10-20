import { lstat, realpath } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";

function inside(root, target, allowRoot) {
  const rel = relative(root, target);
  return rel === "" ? allowRoot : rel !== ".." && !rel.startsWith("..\\") && !rel.startsWith("../") && !isAbsolute(rel);
}

function gitPath(root, target) {
  const rel = relative(root, target).replaceAll("\\", "/").toLowerCase();
  return rel === ".git" || rel.startsWith(".git/");
}

const DEVICES = new Set(["con", "prn", "aux", "nul", ...Array.from({ length: 9 }, (_, i) => "com" + (i + 1)), ...Array.from({ length: 9 }, (_, i) => "lpt" + (i + 1))]);

// Windows opens "CON", "nul.txt" and "aux.gd" as devices, not workspace files,
// and silently strips trailing dots and spaces from a name. Either one would let
// a tool call leave the workspace or read the console instead of a game file.
function devicePath(value) {
  if (process.platform !== "win32") return false;
  return value.split(/[\\/]+/).some(segment => {
    if (!segment || segment === "." || segment === "..") return false;
    if (segment.endsWith(".") || segment.endsWith(" ")) return true;
    return DEVICES.has(segment.split(".")[0].trim().toLowerCase());
  });
}

// Resolve existing ancestors as well as the target: write/move destinations may
// not exist yet, and a parent can be a symlink or a Windows junction.
async function resolvedTarget(target) {
  try {
    await lstat(target);
    return await realpath(target); // A dangling symlink is rejected, not skipped.
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    // lstat succeeds for a dangling link, so do not mistake it for a missing file.
    if (await lstat(target).then(() => true, (e) => e.code === "ENOENT" ? false : Promise.reject(e))) {
      throw new Error("Dangling workspace link.");
    }
    const parent = dirname(target);
    if (parent === target) throw error;
    return resolve(await resolvedTarget(parent), relative(parent, target));
  }
}

export async function workspacePath(cwd, value, { destructive = false } = {}) {
  if (typeof value !== "string" || !value || isAbsolute(value)) throw new Error("Expected a relative workspace path.");
  if (devicePath(value)) throw new Error("Windows device names and trailing dots or spaces are not workspace paths.");
  const root = resolve(cwd);
  const target = resolve(root, value);
  if (!inside(root, target, !destructive)) throw new Error("Path targets the workspace root or escapes the workspace.");
  const realRoot = await realpath(root);
  const realTarget = await resolvedTarget(target);
  if (!inside(realRoot, realTarget, !destructive)) throw new Error("Resolved path targets the workspace root or escapes the workspace.");
  if (destructive && (gitPath(root, target) || gitPath(realRoot, realTarget))) throw new Error("GameSmith reserves .git metadata; use the Git tools instead.");
  return target;
}
