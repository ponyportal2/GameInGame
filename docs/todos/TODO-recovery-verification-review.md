# Recovery and verification review

- [x] Preserve the original objective when an accepted first turn has no saved native conversation; cover worker records and host recovery.
- [x] Select all inventory consumers of changed shared modules, and conservatively cover inherited controllers.
- [x] Rerun the original selection when prior evidence was invalidated by changing inputs.
- [x] Run focused regressions, then the unified release verification with persisted evidence.
- [x] Rebuild the Windows package and record results and limitations.

Focused evidence: `gamesmith-verify-ArUkZ1/results.json` passed 10 steps; `gamesmith-verify-13ghma/results.json` passed verification plus the expanded native recovery matrix. Final verification below includes the additional AGY/OMP unsaved-session records. No real provider calls are required.

Final evidence: `%TEMP%/gamesmith-review-20261016-recovery-final/results.json`.
Command: `node tools/testing/verify.mjs --suite release --output errors --build-package --artifacts %TEMP%/gamesmith-review-20261016-recovery-final`.
All 81 steps passed uninterrupted, with no reuse, no failed/blocked/interrupted steps, and no changing inputs (1106.8 seconds). Node: 219 passed, zero failed, one existing intentional native-provider test skip. Pi emulator: 140/140; migration: 1/1; windowed ownership: 29/29. All 37 isolated host runners passed, including six adapters' first-turn discarded-session recovery through their real assembled workers. Node coverage also checks AGY before-init exit, OMP first-turn backend death and Crush's unsaved HTTP rejection. The package was rebuilt before contents/structure validation. Launcher tests and all three local acceptance steps passed. No paid model calls or GitHub CI were started. This final evidence annotation was added afterward; product and test code stayed frozen throughout the run.
