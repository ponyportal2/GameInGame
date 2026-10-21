# Runtime search recovery

- [x] Add failing regressions for ignored arguments, depth recovery and large paged runtime search.
- [x] Reject unknown inspection/search arguments and return actionable incomplete-search guidance.
- [x] Clarify focused search, query-relative pagination and resource limitations.
- [x] Verify shared consumers and rebuild/verify the Windows package.
- [x] Commit, push and verify the remote revision.

Keep system rg source/runtime search, bounded output and observed identity handles. Do not add reload or resource editing machinery.

TDD: `gamesmith-verify-zH0gGo` reproduced the failures (2 entries failed).
First fix verification: `gamesmith-verify-xhivHZ` passed both entries plus import/setup.
Added shared-harness recovery/rejection checks before final verification.

Final verification: `node tools/testing/verify.mjs --suite affected --build-package --output summary`
passed all 84 entries, with zero failures, skips or reused results (1059.6 seconds).
Evidence: `%TEMP%/gamesmith-verify-xPffhn/results.json`.
Includes canonical assembly/shared harness checks, the Tetriscat depth-four mesh
discovery and live hide regression, 900-node sparse paged system-rg fixture,
existing output limits, Godot host tests, Windows package contents/structure and
launcher checks. No real-provider timing replay was run; player games were not edited or reloaded.
