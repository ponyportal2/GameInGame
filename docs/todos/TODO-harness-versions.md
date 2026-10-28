# Harness version audit (2026-10-29)

Scope: every CLI in `tools/agent/harnesses.json`. Policy for open-source and
small-vendor harnesses is the newest release that is at least 7 days old; huge
vendors (Kiro/AWS, Copilot/GitHub, Codex/OpenAI, Cursor) may track latest. Only
the installed version is supported.

## Changed in this pass

- **OpenCode** `2.1.2` — v1 is gone, so the adapter moved from the HTTP/SSE
  `opencode serve` API to the v2 `opencode acp` stdio backend. The confined
  `build` agent is expressed as OpenCode 2's ordered permission-rule list,
  sessions use `session/new`/`session/load`, and Stop sends `session/cancel`.
  Kilo keeps the shared HTTP/SSE transport. 2.1.3 is 6.2 days old, 2.1.4 is
  5.3 and 2.2.0 is 1.4, so 2.1.2 is the newest release at or above the floor.
- **Copilot** `1.0.105` — the installed CLI removed `--no-remote`, so every
  session exited with code 1. The adapter no longer passes that flag; remote
  access is off by default in 1.0.105. Live acceptance passed 36/36 assertions.
- **Kiro** `kiro-cli 2.35.1` — V3 engine. `acp --agent-engine v3`, restricted
  profile via `session/set_mode`, autopilot forced off. Live acceptance passed
  (2/2). See `TODO-kiro.md`.
- **Crush** `0.98.1` (was 0.96.1). Published 2026-10-09, well past the floor;
  0.98.2 (2026-10-23) is only 5 days old. Gate, fixture and docs updated. See
  `TODO-crush.md`.
- **Command-code** `1.86.3` (was 1.82.1). Newest release at or above the 7-day
  floor: 1.86.3 is 7.6 days old while 1.87.0 (6.98 d), 1.87.1 (6.75 d) and
  1.88.x are still inside it. `command-code acp` still has no root `--mod`
  option, so the inert loader is unchanged. The native provider-boundary suite
  passed 38/38 requests against the real CLI, and the ACP unit suites are 14/14.
- **Pi** stays `1.3.0` (12.9 days old). 1.4.0 (2026-10-21T22:48Z) is both inside
  the 7-day floor (6.8 d) and regresses the diagnostics contract: two real-Pi
  checks fail — "persisted reload diagnostics are acknowledged at the session
  boundary" and "delivered diagnostic notice is not announced again". The
  notice is appended to the branch but its receipt never commits, so the same
  notice is announced twice.

- **Live acceptance on the new pins** — `command_code_integration_runner.gd`
  passed 14/14 assertions in 169.8 s against installed `command-code 1.86.3`
  (evidence `%TEMP%/gamesmith-verify-9tqJWa/results.json`), and
  `opencode_integration_runner.gd` passed 9/9 assertions in 113.1 s against
  installed `opencode 2.1.2` (evidence `%TEMP%/gamesmith-verify-jAP6M4/results.json`).

## Already current, no change

| Harness | Installed | Newest at or above the 7-day floor |
| --- | --- | --- |
| Cline | 3.0.73 | 3.0.73; 3.0.74 is 2.6 days old |
| Kilo | 7.8.15 | 7.8.15; 7.8.16 is 5.8 days old |
| Cursor | 2026.10.22-27dcf5f | current |
| Grok Build | 1.0.70 | current |
| AGY | 1.4.9 | current |
| Kimi | 2.4.0 | current |
| OMP | 18.12.5 | current |

## Known blockers

- **Codex** reports `0.164.0` from the standalone installer on `PATH`, while the
  npm copy is `0.165.0` and is shadowed. `codex update` fails with "Downloaded
  Codex package archive did not contain the expected package layout", so the
  installed CLI stays at 0.164.0. The adapter has no version gate and is
  unaffected.
- **Pi diagnostics e2e** has two failures that predate this pass and reproduce
  on the 1.3.0 baseline: `pi_integration_runner.gd` finishes 138 passed /
  2 failed. They are unrelated to the harness version work; the Pi sources are
  unchanged apart from the pinned install string.
- **Cline live acceptance** cannot run in this profile: the installed
  `cline 3.0.73` has no saved native login, so every session aborts with
  `Authentication required: Call authenticate before starting a session` and
  the write/stream/model assertions fail as a knock-on. The adapter itself is
  on the floor-eligible version and its provider/model confirmation check
  passes; re-run `cline_integration_runner.gd` after `cline auth` to close it.
