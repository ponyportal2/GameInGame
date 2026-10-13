# Kiro review corrections

- [x] Add failing regressions for custom KIRO_HOME and per-turn prompt contents.
- [x] Honor native home and keep instructions solely in the custom profile.
- [x] Remove copied Kiro support implementations; test the actual controller assembly.
- [x] Run Node, host, live and packaged checks; rebuild and commit/push.

Keep V2 explicit; do not start GitHub CI. Preserve screenshots and native settings.

## Implementation

`nativeSessionFile()` respects `KIRO_HOME`, falling back to `~/.kiro`.
Only the player message is sent in each ACP turn; the restricted custom profile
keeps the full host instructions. Both regressions failed before these changes.

Kiro no longer owns copied workspace/process policy implementations. Its two
source-tree facades re-export the existing shared implementations; unused local
host-tools/workspace-paths copies are removed. The controller still assembles its
existing flat runtime from Codex/Pi/OpenCode/agent support sources. Node transport
tests now read those actual controller mappings and copy precisely that bundle
before launching the worker/MCP, covering the deployed import graph rather than
a different source-tree graph. No other harness mapping or protocol changed.

132 Node tests pass with zero failures, including custom-home resume and two
consecutive exact player messages with profile-only instructions. Rebuilt Windows
PCK and isolated packaged-content check passed.

## Final verification (2026-10-14)

- All 132 Node tests passed, exit 0.
- Targeted Kiro lifecycle, shared Stop and harness/settings/switching host runners
  completed together, exit 0. This was a targeted run, not another full host run.
- Installed Kiro 2.30.0 real acceptance passed all 24 checks with native Auto:
  edits, headless testing, streaming, history/backend reuse, reopen, rename,
  65-second reload approval, actual reload and Stop/resume. No visible thinking
  deltas were emitted; no reasoning-stream claim is made.
- Isolated rebuilt PCK passed content verification and all 29 Kiro lifecycle
  fixture checks, including forced Stop during stalled start/turn/cancel.
- Logs: `%TEMP%/gamesmith-kiro-review-node.log`,
  `gamesmith-kiro-review-host.log`, `gamesmith-kiro-review-live.log`,
  `gamesmith-kiro-review-package.log`, `gamesmith-kiro-review-package-fixture.log`.

Custom KIRO_HOME is verified by assembled-runtime transport fixture, not a live
model run using a relocated login. Live acceptance used the existing native login
and settings. No global settings/credentials changed and no GitHub CI started.
