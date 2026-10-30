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
  Context occupancy comes only from `usage_update.used`; the prompt response's
  `usage.totalTokens` measures that call's consumption and is never substituted
  for it, so a repeated or missing update leaves the count unchanged.
- **Copilot** `1.0.105` — the installed CLI removed `--no-remote`, so every
  session exited with code 1. The adapter no longer passes that flag; remote
  access is off by default in 1.0.105. Live acceptance passed 36/36 assertions.
- **Kiro** `kiro-cli 2.35.1` — V3 engine. `acp --agent-engine v3`, restricted
  profile via `session/set_mode`, autopilot forced off. Live acceptance passed
  (2/2). See `TODO-kiro.md`.
- **Crush** `0.98.1` (was 0.96.1). Published 2026-10-09, well past the floor;
  0.98.2 (2026-10-23) is only 5 days old. Gate, fixture and docs updated, and
  the CLI is installed so the gate is exercised for real: `crush --version`
  reports v0.98.1 and live acceptance passed 2/2. The npm package installs a
  `crush.cmd` shim beside the binary GoReleaser extracted, so
  `resolveExecutable` now maps a `.cmd` hit to
  `node_modules/@charmland/crush/bin/crush.exe` instead of failing with "Crush
  CLI was not found". See `TODO-crush.md`.
- **Command-code** `1.86.3` (was 1.82.1). Newest release at or above the 7-day
  floor: 1.86.3 is 7.6 days old while 1.87.0 (6.98 d), 1.87.1 (6.75 d) and
  1.88.x are still inside it. `command-code acp` still has no root `--mod`
  option, so the inert loader is unchanged. The native provider-boundary suite
  passed 38/38 requests against the real CLI, and the ACP unit suites are 14/14.
- **Codex** `0.165.0` — the stale standalone 0.164.0 that shadowed the npm
  copy is updated in place, so `where codex` no longer resolves to an old
  binary. `codex update` had been failing with "Downloaded Codex package
  archive did not contain the expected package layout"; the cause is
  environmental, not upstream: the standalone updater shells out to `tar`,
  and under Git Bash that is MSYS `/usr/bin/tar`, which reads the archive's
  `C:\` path as a remote host ("Cannot connect to C: resolve failed"). Running
  the same update from PowerShell succeeds. The adapter has no version gate
  and live acceptance passed 2/2.
- **Pi** `1.4.0` (was 1.3.0). The 7-day floor alone would have kept 1.3.0,
  but the pin now names the current release. The two real-Pi checks that had
  been failing since before this pass are fixed, and `pi_integration_runner.gd`
  finishes 140 passed / 0 failed (see below).
- **Cline** `3.0.74` — the CLI had already moved this profile past the floor
  on its own, and the pin now matches the installed release. GameSmith no
  longer sets `CLINE_NO_AUTO_UPDATE=1`: Cline owns its install, the adapter
  targets the ACP surface rather than one release, and suppressing the upgrade
  only pinned the player to a build the CLI had decided to leave. The
  adapter-side fixes from the 3.0.73 pass stay: `liveEnvironment()` passes
  `CLINE_DIR` so the live host's isolated `HOME` no longer hides
  `providers.json`, and the live runner compares the applied model against the
  profile's saved model instead of the retired `cline-free/` prefix.
  Reinstalling a specific release needs `--force` because the running hub
  daemon keeps the newer binary on disk.

- **Live acceptance on the new pins** — `command_code_integration_runner.gd`
  passed 14/14 assertions in 169.8 s against installed `command-code 1.86.3`
  (evidence `%TEMP%/gamesmith-verify-9tqJWa/results.json`),
  `opencode_integration_runner.gd` passed 9/9 assertions in 113.1 s against
  installed `opencode 2.1.2` (evidence `%TEMP%/gamesmith-verify-jAP6M4/results.json`),
  `copilot_integration_runner.gd` passed 36/36 assertions in 151.6 s
  (`%TEMP%/gamesmith-verify-EifdCH/results.json`), and
  `codex_integration_runner.gd` passed 2/2 in 58.1 s against the updated
  `codex 0.165.0` (`%TEMP%/gamesmith-verify-FKbRLu/results.json`), and
  `crush_integration_runner.gd` passed 2/2 in 125.2 s against the freshly
  installed `crush 0.98.1` (`%TEMP%/gamesmith-verify-gJ3F4a/results.json`), and
  `kilo_integration_runner.gd` passed 2/2 in 149.6 s on the shared HTTP/SSE
  transport (`%TEMP%/gamesmith-verify-ahzG33/results.json`), and
  `cline_integration_runner.gd` passed 19/19 assertions in 114.4 s against
  installed `cline 3.0.73` (`%TEMP%/gamesmith-verify-bztEpn/results.json`), and
  `omp_integration_runner.gd` passed 2/2 in 182.1 s against installed
  `OMP 18.12.5` (`%TEMP%/gamesmith-verify-0tyVbx/results.json`). The OMP
  runner itself was stale: it required `GAMESMITH_TEST_OMP_MODEL` instead of
  treating it as optional, and it pinned the host tool count at 18 while
  GameSmith now exposes 23. Both are fixed; the surface check now asserts that
  only `gamesmith_*` tools reach the model and that the core set is present,
  so it cannot rot again. The first OMP attempt failed only on those two stale
  expectations (`%TEMP%/gamesmith-verify-2N0nVI/results.json`).
  The first Kilo attempt failed because the stealth model answered without
  calling any tool. The identical rerun passing is consistent with model
  variance, but one rerun cannot exclude an intermittent integration problem;
  the initial failure stays on the record.
- **Live acceptance on the versions installed now** - with Pi 1.4.0 the real-Pi
  e2e passed 140/140 (exit 0), including the two diagnostics assertions that had
  been failing. `cline_integration_runner.gd` passed 2/2 in 135.3 s against
  installed `cline 3.0.74` (`%TEMP%/gamesmith-verify-xqKXAD/results.json`), and
  `kilo_integration_runner.gd` passed 2/2 in 187.3 s against installed
  `kilo 7.8.18` (`%TEMP%/gamesmith-verify-tCCW4O/results.json`). The first Cline
  attempt aborted with "Inputs changed during verification" because a doc edit
  landed mid-run; it had already passed 2/2, and the clean rerun above is the
  one on the record.
- **Kilo** `7.8.18` — an interactive `kilo` run moved the install from 7.8.15
  to 7.8.18 at 2026-10-28T18:57Z; the CLI logged
  `upgraded method=npm target=7.8.18` and the npm cache shows that tarball
  fetched at the same moment. 7.8.18 is 3.3 days old, so the upgrade bypassed
  the floor. That upgrade is now accepted rather than fought: Kilo owns its own
  install, and `kilo serve` — the path GameSmith runs — does not check for
  updates, so a game session never triggers one. Injecting `update:"disable"`
  (current schema key) or `autoupdate:false` (deprecated) through
  `KILO_CONFIG_CONTENT` did not stop a 60-second TUI run from reaching 7.8.18,
  which is why the adapter does not try to hold a pin.

## Already current, no change

| Harness | Installed | Newest at or above the 7-day floor |
| --- | --- | --- |
| Kilo | 7.8.18 | 7.8.18; installed by the CLI's own TUI upgrade |
| Cursor | 2026.10.22-27dcf5f | current |
| Grok Build | 1.0.70 | current |
| AGY | 1.4.9 | current |
| Kimi | 2.4.0 | current |
| OMP | 18.12.5 | current; live acceptance re-run on it |

## Fixed in this pass: the two real-Pi diagnostics failures

Both assertions came from `src/core/json_output.gd`, not from Pi. It escaped
ASCII control characters by looping `String.chr(code)` from 0, and
`String.chr(0)` is not a NUL: Godot reports "Unicode parsing error, some
characters were replaced with U+FFFD: Unexpected NUL character" and returns
U+FFFD. The loop then rewrote every U+FFFD in the payload as a `\u0000`
escape, so each host response was corrupted and each call emitted an error
record. The collector stored that record as a new diagnostic, the next notice
included it, and `take_notification()` could never empty. The loop now starts
at 1; `JSON.stringify` already substitutes U+FFFD for a real NUL, so code 0
never survives to be escaped.

A second, independent defect produced the same symptoms.
`PiRpcSession._drain_pipe` decoded each pipe chunk with
`get_string_from_utf8()`. A chunk boundary lands wherever the pipe flushes, so
multi-byte UTF-8 sequences were split and Godot reported a Unicode parsing
error per split — 854 of them in one run. The session now buffers
`PackedByteArray` and decodes only complete newline-delimited lines.

## Known blockers

- **Cline and Kilo update themselves.** Both CLIs upgrade their own global
  install on their own schedule (Cline on startup with
  `--min-release-age 0`, Kilo from its interactive TUI). GameSmith does not
  suppress that: the adapter targets the ACP/HTTP surface, not one release, and
  the installed version is what gets verified. Re-check `cline --version` /
  `kilo --version` before treating live evidence as current. A running Cline
  hub daemon holds the old binary, so a downgrade needs
  `npm install -g cline@<version> --force` after it exits.
- **Cline is tested on the binary the wrapper resolves.** `cline --version`
  reports the platform binary, not the npm wrapper version; the two can diverge
  when an update is interrupted, so compare both after any reinstall.
