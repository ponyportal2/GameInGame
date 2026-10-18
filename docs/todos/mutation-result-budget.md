# Complete mutation outcomes

- [x] Add regressions for oversized batches rejected before writes and complete partial outcomes.
- [x] Preflight bounded mutation results, including setter-altered readback and refreshed handles.
- [x] Verify shared consumers and packaged runtime; preserve runtime rg search.
- [x] Record evidence, rebuild package, commit and verify pushed revision.

Evidence so far:
- Red host regression: `gamesmith-verify-sIWSPD/results.json` (both expected budget assertions failed).
- Focused host/output tests: `gamesmith-verify-zHcM7i/results.json`; host/output passed, new fixture failed and was corrected.
- Shared assembled consumers: `gamesmith-verify-TVpoSB/results.json` passed. Real partial outcomes, setter invalidation, large readback/rename, newline/control/Unicode strings survive both shared output caps in all 14 harnesses.
- Escaping regression exposed raw ASCII controls from Godot JSON.stringify; shared host response serialization now escapes surviving controls.
- No real-provider tests and no player-game edits/reloads.

Final verification:
- `node tools/testing/verify.mjs --suite affected --output summary --build-package`: `gamesmith-verify-5b57Pw/results.json`, 69 passed, zero test failures, 15 blocked by Windows `EPERM` renaming the runner's progress file. Package build and all 163 runtime-property assertions passed; inputs remained unchanged.
- `node tools/testing/verify.mjs --rerun-failed .../gamesmith-verify-5b57Pw/results.json --output summary`: `gamesmith-verify-Y4pcgt/results.json`, 16 passed (15 previously blocked entries plus import), zero failures/blocks/skips/reused results. Includes packaged preflight rejection, 200-node recolor, structure and launcher checks.
- All 82 selected tests passed across these runs. Rebuilt `GameSmith-Windows/GameSmith.pck`; runtime rg coverage remains passing. The progress-file orchestration error did not require production changes.
- Accepted results retain complete per-target outcomes. Unusually large non-string setter readback or renamed paths return explicit post-write errors with applied names and original identity, rather than losing the whole outcome to truncation; bounds are documented in `docs/runtime-properties.md`.
