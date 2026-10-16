# Recovery review follow-up

- [x] Reproduce abandoned streamed output and initialization retry regressions.
- [x] Reconcile transient chat before recovery; fail initialization immediately.
- [x] Verify focused recovery, native session recovery and lifecycle checks.
- [x] Update documentation, rebuild Windows package and verify packaged recovery.
- [x] Commit and push without starting GitHub CI.

No live Codex requests without an explicit gpt-6-luna model flag.

Evidence: complete Node suite passed 211 tests with one intentional skip (212 total), using four concurrent test files. An earlier unbounded-concurrency run timed out in the OMP idle-exit test; it passed alone and in the bounded complete run. Source and packaged recovery regressions verify streamed partial removal, persisted tool retention, and immediate startup/admission/completion initialization failure. Packaged content verification passed. All 36 source host runners passed in one uninterrupted run, including stale Kilo failure with recovery enabled and immediately available reset controls. No real-provider calls or GitHub CI runs were started.

Implementation keeps lifecycle classification separate from retirement: `initialization_failed` stops immediately; `runtime_failed` requests backend retirement without disabling ordinary turn recovery. This distinction matters for first-turn provider failures in the ACP harnesses as well as Command-code, AGY, Crush and OMP.

Local evidence:
- Node: `%TEMP%/gamesmith-recovery-review-node-final.log`.
- Source host run: `%TEMP%/gamesmith-tests-8quqfR` (49 shared recovery assertions; 13 native harness recovery adapters).
- Rebuilt isolated package: `%TEMP%/gamesmith-recovery-review-pack-whqsw0mb` (49 recovery assertions and package-content checks).
