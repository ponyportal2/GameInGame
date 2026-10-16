# Review fixes

- [x] Regression: stuck OpenCode Stop and startup cancellation.
- [x] Regression: partial/lost SSE final answer and successful HTTP reconciliation.
- [x] Per-game ownership across agent requests, switching, rename and deletion.
- [x] POSIX complete descendant cleanup, including detached backend groups.
- [x] Update manual Windows/Linux verification lists; keep automatic CI disabled.
- [x] Run targeted and full checks and rebuild the Windows package.
- [x] Commit and push.

Implementation decisions:

- Stop has a five-second cancellation grace in the host. Ordinary agent requests and HTTP startup/model calls retain no deadline. Healthy cancellation retains the backend/session; forced Stop kills the tree.
- An exclusive Windows named pipe / Linux abstract socket owns each canonical game path. There are no lockfiles or lease-expiry timers. Opening another window is allowed; editing and conflicting management operations are denied. Ownership transfers across harness changes/rename and releases on closing the game or host exit.
- Final HTTP text parts are canonical. Part cursors append missing suffixes; divergent snapshots cause the host to refresh the persisted transcript. SSE transport errors remain diagnostic warnings and do not alone invalidate a successful HTTP response.
- Linux shutdown freezes and enumerates descendants before killing them, including detached backend groups. Pipes close only afterward.

Local verification (2026-10-13; no remote CI run claimed):

- Node protocol/transport suites: 48 passed, 0 failed on Windows Node 24.16 and WSL Ubuntu Node 22.19.
- Windows host default runners: all passed, with the maintenance unit fixture rerun after explicitly mocking ownership, plus final strengthened ownership/Stop regressions. Intentional broken-game fixtures emit expected parse diagnostics.
- Installed Pi with local fake provider: all 140 integration checks passed, including compaction, retries, session restart and migration.
- Linux Godot 4.7.2: ownership, forced Stop (stalled startup/abort/settlement), detached-child shutdown, OpenCode lifecycle, harness switching, Command-code lifecycle and compaction passed. Process assertions inspect native process state, excluding zombies; they do not use Godot's child-only PID check for grandchildren.
- Windows PCK rebuilt; bundled adapters/ownership/process-tree helpers and self-contained package verification passed. No paid-provider or live model acceptance was needed for these transport/lifecycle changes.
- Logs are kept outside the repository under the OS temporary directory (`review-node-final.log`, `review-host-remainder.log`, `review-host-final-regressions.log`, `review-pi-e2e.log`, `review-linux-host-verified.log`, `review-linux-extra.log`, `review-linux-node.log`, `review-package.log`).
