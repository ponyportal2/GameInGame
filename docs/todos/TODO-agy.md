# AGY CLI integration (experimental)

- [x] Inspect installed AGY 1.3.4 and native stream-JSON/MCP/session protocol.
- [x] Add failing adapter/permission/transport regressions before implementation.
- [x] Implement persistent native turns, explicit resume, Stop retirement, GameSmith MCP and native hook policy.
- [x] Integrate creation/switching, native-owned settings, session reset, ownership, launcher and package checks.
- [x] Run deterministic Node/host/launcher tests and packaged fixture acceptance.
- [x] Probe installed AGY startup, MCP discovery, error recovery and explicit resume. Model acceptance is unavailable (native location error).
- [x] Document experimental status and build Windows package.
- [x] Commit and push verified changes.

No successful model invocation or live generated-game acceptance may be claimed. Native hook execution during an actual model tool call also remains unverified until inference is available.

## Local verification

- Node: `node --test tests/*.test.mjs`: 101 passed, 0 failed, including eight AGY tests. Tool-step regression first failed, then passed after correcting the native `tool` event fields (including final-only snapshots).
- Windows launcher: `go test ./...` passed; rebuilt `GameSmith.exe` includes AGY detection.
- Targeted AGY lifecycle, harness settings/switching and ownership: passed in `%TEMP%/gamesmith-tests-zyUvho`.
- Default host run: prior runners passed, but stopped on one Cursor PID-change assertion in `gamesmith-tests-1rFW9I`. Cursor, Grok Build, AGY and process shutdown all passed on the separate remaining-runner invocation in `gamesmith-tests-qmmoOl` (exit 0). All 24 runners were covered across these runs, but this is not a clean uninterrupted full-suite result. The cause of the initial Cursor assertion failure was not established.
- Final PCK export, structural package-content regression and `verify_windows_package.py`: passed.
- Installed AGY startup/MCP discovery and explicit conversation resume: passed in `%TEMP%/gamesmith-agy-native-FDeEIs`; both model requests returned the expected unsupported-location error. No probe processes remained afterwards.
- Packaged fixture lifecycle: passed in `%TEMP%/gamesmith-agy-package-fixture-jStzuH`; final PCK fixture rerun after the tool-event correction also passed in `%TEMP%/gamesmith-agy-package-fixture-n7lkGK`.
- Automatic CI remains disabled; these are local Windows results.
