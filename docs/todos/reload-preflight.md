# Multi-frame reload preflight

- [x] TDD: isolated execution errors, process/physics counts, cancellation, changed code and cleanup.
- [x] Reuse test-process smoke windows and gate agent/manual full reloads.
- [x] Preserve existing agent test sessions and synchronous host startup checks.
- [x] Focused source and packaged verification.
- [x] Commit/push and verify remote.

Scope: full reload only. No additive-node tools, raw input expansion, rollback,
source snapshots or general test-plan language.

Agent-approved and manual Reload now start a private, separate headless test
process. Acceptance requires at least four completed process ticks, three
completed physics ticks, no captured errors, and clean shutdown. The host then
performs its existing synchronous construction/startup check. Initial manual
Run (including snapshot fallback) is unchanged. The smoke-window facility is
reusable by later late-injection preflight work; no child-injection tools ship
in this patch.

Cancellation, concurrent reloads, leaving the game, timeout and cleanup failure
are bounded. Independent agent test sessions are preserved. Code/resource
fingerprints detect changed inputs before live application (10,000 files /
64 MiB cap, rejecting links); media, arbitrary data and runtime state are not
snapshotted. Preflight success does not guarantee input-driven behavior or live
correctness. A failed host attempt may already have side effects and reports
unknown live modification rather than claiming rollback.

Verification on 2026-10-18 (local deterministic fixtures; no provider calls):

- TDD initially failed because `checked_reload` did not exist.
- `%TEMP%/gamesmith-verify-mVqVt7/results.json`: 15 passing entries, covering
  output/search contracts, all 14 assembled harnesses and prompt paths, manual
  reload/focus, approval settings, test-process controls, ownership/Stop and
  Codex/Cline lifecycle fixtures. Two failures prompted a queued-controller
  teardown fix and preservation of tool-level preflight diagnostics.
- `%TEMP%/gamesmith-verify-JRCx3i/results.json`: runtime-properties and OpenCode
  lifecycle fixtures passed after those fixes; package structure passed.
  Its package fixture failed on a duplicate local declaration (corrected).
  One source-change assertion failed, then passed in an isolated rerun
  (`gamesmith-verify-fHdFpO`, 39 assertions). The fixture now uses an explicitly
  absent, unique dependency filename and prints rejection reasons on failure.
- Final failed-selection rerun with rebuilt Windows PCK:
  `%TEMP%/gamesmith-verify-ayBhnr/results.json`, 4/4 entries passed, 122.2 seconds.
  Dedicated preflight fixture: 40 assertions, including process/physics/deferred
  errors, startup/compile errors, early exit, cleanup errors/hangs, execution
  timeout, cancellation, changed code, final host-only failure, JSON round trip
  and owner teardown. Packaged execution passed tick/cleanup acceptance,
  physics-error rejection preserving the live instance and diagnostics, plus
  existing compact pagination/mutation of 200 walls.

No full-suite rerun or real-model acceptance was performed. Focused host checks
use actual isolated Godot processes; native harness tests use deterministic CLI
fixtures. The deliberate abrupt-owner teardown fixture emits Godot object/
resource leak warnings at exit; structured assertions and process-reaping
checks pass. These warnings were not treated as successful rollback evidence.
