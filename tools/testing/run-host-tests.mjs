// Run host tests with isolated application data on Windows or Linux.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const [godot, ...requestedScripts] = process.argv.slice(2);
if (!godot) throw new Error("Usage: node tools/testing/run-host-tests.mjs <godot> [test_runner.gd ...]");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const data = mkdtempSync(join(tmpdir(), "gamesmith-tests-"));
const env = { ...process.env, APPDATA: data, HOME: data, XDG_DATA_HOME: join(data, "data") };
console.log(`Test data: ${data}`);
const scripts = requestedScripts.length ? requestedScripts : ["test_runner.gd", "reliability_runner.gd"];
for (const [index, script] of scripts.entries()) {
  const result = spawnSync(resolve(godot), ["--headless", "--path", root,
    "--log-file", join(data, `engine-${index}.log`), "--script", `res://tests/${script}`],
  { env, windowsHide: true, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
