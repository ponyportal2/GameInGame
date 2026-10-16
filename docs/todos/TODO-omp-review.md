# OMP review follow-up

- [x] Reproduce idle backend death and delayed settlement with deterministic tests.
- [x] Retire the worker on native backend exit and consume every agent settlement.
- [x] Bound duplicate-call tracking without weakening replay rejection.
- [x] Verify source and packaged OMP lifecycle and real selected-model acceptance.
- [x] Rebuild the Windows package and record results for publication.

Keep the persistent RPC architecture, explicit native history and native-owned
model/provider/reasoning/compaction settings. Do not start GitHub CI.

Both P2 regressions failed against the previous worker: the idle adapter remained
alive, and the second turn completed with truncated text after consuming the
first turn's late settlement. Both pass after the fix. Local-only prompt
admission remains exempt from waiting for agent settlement.

Replay coverage generates 2,050 calls, evicts the first IDs from the 4,096-entry
recent cache, then rejects replay within that active turn and replay of a recent
call in the next turn. Active-turn IDs are retained until completion. The fixture
trace uses append rather than repeatedly rewriting its growing log; the first
stress run timed out on the old fixture logging path, then passed after that
test-only optimization.

Complete Node suite: 187 tests, 186 passed, zero failed, one optional Command-code
native-provider test skipped. `%TEMP%/gamesmith-omp-review-node.log`.

Focused source host run passed OMP lifecycle (31 checks), harness switching,
editing ownership and process-tree shutdown. Evidence:
`%TEMP%/gamesmith-tests-ZJzl1H/`. Killing the idle backend produces Godot pipe-EOF
diagnostics in the engine log; recovery succeeds and the next request resumes
the same saved native session. No shared pipe implementation was changed.

Final focused OMP Node tests: 17/17, including event-order assertions without a
wall-clock minimum, local-only admission and the bounded replay cache.
Source live acceptance: 28/28 with installed OMP 18.10.3 and the selected
`dots-studio/dots-3-note-preview:free` model. Evidence:
`%TEMP%/gamesmith-tests-tTfMuY/engine-0.log`.

Final rebuilt PCK structural contents and lifecycle passed (31/31). Evidence:
`%TEMP%/gamesmith-omp-package-i_yl333_/`.
Packaged real acceptance also passed 28/28, native exit 0, with the same selected
free model. Both live runs cover edits, headless testing, streaming, history
reuse/reopen/rename, 65-second reload approval, actual reload and Stop/resume.
The broader 32-runner suite was not repeated for this OMP-only change; four
relevant source runners and the complete Node suite were run instead. No
GitHub Actions run was started. Windows is verified; Linux remains untested.
