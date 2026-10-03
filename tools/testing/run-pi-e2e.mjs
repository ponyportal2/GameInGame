// Portable Pi acceptance runner. Uses the globally installed Pi and a local fixture.
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const [godot, pi = process.platform === "win32" ? "pi.cmd" : "pi"] = process.argv.slice(2);
if (!godot) throw new Error("Usage: node tools/testing/run-pi-e2e.mjs <godot> [pi]");
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const data = mkdtempSync(join(tmpdir(), "gamesmith-pi-tests-"));
const log = join(data, "requests.jsonl");
console.log(`Pi test data: ${data}`);
const server = spawn(process.execPath, [join(root, "tools/fake-openai-endpoint/pi-server.mjs")], {
  env: { ...process.env, GAMESMITH_PI_FAKE_PORT: "0", GAMESMITH_PI_FAKE_LOG: log },
  windowsHide: true, stdio: ["ignore", "pipe", "inherit"],
});
try {
  const port = await new Promise((accept, reject) => {
    let output = "";
    server.on("error", reject);
    server.on("exit", (code) => reject(new Error(`Fixture exited: ${code}`)));
    server.stdout.on("data", (chunk) => {
      output += chunk;
      const ready = output.match(/READY (\d+)/);
      if (ready) accept(ready[1]);
    });
  });
  const child = spawn(resolve(godot), ["--headless", "--path", root,
    "--log-file", join(data, "engine.log"), "--script", "res://tests/pi_integration_runner.gd"], {
    env: { ...process.env, APPDATA: data, HOME: data, XDG_DATA_HOME: join(data, "data"),
      GAMESMITH_PI_BIN: pi, GAMESMITH_PI_FAKE_URL: `http://127.0.0.1:${port}/v1`, GAMESMITH_PI_FAKE_LOG: log },
    windowsHide: true, stdio: "inherit",
  });
  process.exitCode = await new Promise((accept, reject) => {
    child.on("error", reject);
    child.on("exit", (code) => accept(code ?? 1));
  });
} finally {
  server.kill();
}
