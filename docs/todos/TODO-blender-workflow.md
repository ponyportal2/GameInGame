# Blender workflow improvements from Tetriscat

- [x] Regress portable asset access from nested scripts, reload, rename and test processes.
- [x] Add exact scene paths, bounded recursive inspection and useful path errors.
- [x] Default Blender status to a compact summary; retain opt-in details and error logs.
- [x] Add a tested asymmetric export example and hierarchy/world-space report fields.
- [x] Update all harness schemas and instructions, including rendered Godot verification.
- [x] Run focused and broader host checks, real Blender acceptance, and package checks.
- [x] Rebuild Windows package/launcher and commit/push verified changes.

Do not modify the player's Tetriscat workspace. Preserve existing approval policy and rendered-test permission.

## Verification evidence

- Red regression: nested asset access failed before the helper was installed.
- Rebuilt PCK, isolated packaged checks: assets 10/10, Blender host 129/129, test processes 63/63, package contents passed.
- Real Blender packaged acceptance: 27/27, including exported GLB hierarchy/axis checks, headless Godot loading, a non-flat rendered Godot screenshot, reopen, cancellation and supervisor-death cleanup. Screenshot inspected directly.
- Real installed Command-code provider-boundary emulator: passed, 38 provider requests checked. This verifies the native integration boundary, not a live external model's artistic behavior.
- Launcher Go tests/build and self-contained Windows package verification passed.
- Complete Node suite: 208 passed, 0 failed, 1 intentional skip.
- Initial packaged check exposed a source-reading test assumption (scripts are compiled in the PCK); corrected without weakening behavioral approval checks.
- Initial broad host run exposed shared fixture data: the maintenance runner wrote partial settings, invalidating a later fresh-default assertion. Each runner now gets private application data; settings checks then passed.
- The isolated broad run hit one intermittent existing normal-stop assertion (clean exit code but missing graceful-stop evidence). Its focused reproduction passed 63/63, as did the packaged run. No speculative shutdown change was made.
- All 34 source host runners passed across split runs: eight passed before the shutdown assertion, the test-process reproduction passed, and the remaining 25 runners completed with exit code 0. This is not an uninterrupted complete-suite pass.
- Existing Tetriscat files were not changed. No GitHub CI was started.
