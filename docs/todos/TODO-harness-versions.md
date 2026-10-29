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
- **Pi** stays `1.3.0` (12.9 days old). 1.4.0 (2026-10-21T22:48Z) is inside the
  7-day floor at 6.8 days, which on its own keeps the pin. The two real-Pi
  checks that fail — "persisted reload diagnostics are acknowledged at the
  session boundary" and "delivered diagnostic notice is not announced again" —
  also fail on the 1.3.0 baseline, so they do not establish a 1.4-specific
  regression. 1.3.0 stays because of the floor, not because of that evidence.
- **Cline** `3.0.73` — stays on the floor-eligible release (3.0.74 is 2.6 days
  old) and now passes live acceptance. Two adapter-side gaps had to be closed:
  the live host ran with an isolated `HOME`, so the adapter looked for
  `providers.json` in a temp directory and every session aborted with
  "Call authenticate before starting a session" even though the profile was
  logged in; `liveEnvironment()` now passes `CLINE_DIR` for Cline like it
  already does for Copilot, Crush and OMP. Separately, the CLI upgrades its own
  global install on startup with `npm update --global cline --tag latest
  --min-release-age 0`, bypassing the release-age floor (it moved this profile
  from 3.0.73 to 3.0.74 on 2026-10-29), so the adapter sets
  `CLINE_NO_AUTO_UPDATE=1` for its child: a game session must not rewrite the
  user's toolchain mid-run. Reinstalling 3.0.73 needed `--force` because the
  running hub daemon kept the 3.0.74 binary on disk. The live runner also
  asserted a stale `cline-free/` model prefix; the current free tier id is
  `reflection/beam-free`, so it now compares against the profile's saved model
  instead of a hardcoded prefix.

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
  installed `cline 3.0.73` (`%TEMP%/gamesmith-verify-bztEpn/results.json`).
  The first Kilo attempt failed because the stealth model answered without
  calling any tool. The identical rerun passing is consistent with model
  variance, but one rerun cannot exclude an intermittent integration problem;
  the initial failure stays on the record.
- **Kilo self-updates from the TUI.** An interactive `kilo` run moved the
  install from 7.8.15 to 7.8.18 at 2026-10-28T18:57Z; the CLI logged
  `upgraded method=npm target=7.8.18` and the npm cache shows that tarball
  fetched at the same moment. 7.8.18 is 3.3 days old, so the upgrade bypassed
  the floor. `kilo serve` — the path GameSmith runs — does not check for
  updates: two 75-second probes produced no update activity, and the live run
  left the version unchanged. Injecting `update:"disable"` (current schema
  key) or `autoupdate:false` (deprecated) through `KILO_CONFIG_CONTENT` did
  not stop a 60-second TUI run from reaching 7.8.18, so the adapter cannot
  hold the pin; only the player's global Kilo config can. 7.8.15 was
  reinstalled and live acceptance repeated: 2/2 in 158.0 s
  (`%TEMP%/gamesmith-verify-cW8L9R/results.json`), version still 7.8.15
  afterwards.

## Already current, no change

| Harness | Installed | Newest at or above the 7-day floor |
| --- | --- | --- |
| Kilo | 7.8.15 | 7.8.15; 7.8.16 is 6.7 days old |
| Cursor | 2026.10.22-27dcf5f | current |
| Grok Build | 1.0.70 | current |
| AGY | 1.4.9 | current |
| Kimi | 2.4.0 | current |
| OMP | 18.12.5 | current |

## Known blockers

- **Pi diagnostics e2e** has two failures that predate this pass and reproduce
  on the 1.3.0 baseline: `pi_integration_runner.gd` finishes 138 passed /
  2 failed. They are unrelated to the harness version work; the Pi sources are
  unchanged apart from the pinned install string.
- **Cline self-updates past the floor.** The CLI runs
  `npm update --global cline --tag latest --min-release-age 0` on startup, so
  any ordinary `cline` invocation can move the install to a release younger
  than 7 days. The adapter suppresses it for its own child
  (`CLINE_NO_AUTO_UPDATE=1`), and 3.0.73 is installed, but a manual run outside
  GameSmith can still bump the pin. Re-check `cline --version` before treating
  the live evidence as current. A running hub daemon also holds the old binary,
  so a downgrade needs `npm install -g cline@<version> --force` after it exits.
- **Cline is tested on the binary the wrapper resolves.** `cline --version`
  reports the platform binary, not the npm wrapper version; the two can diverge
  when an update is interrupted, so compare both after any reinstall.
