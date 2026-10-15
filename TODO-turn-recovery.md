# Shared unsuccessful-turn recovery

- [x] Add failing host regressions for bounded retries, continuation, transcript ownership and Stop.
- [x] Implement shared 8/16/32/64 backoff using existing native completion signals.
- [x] Verify Pi and shared native-controller paths; preserve native histories and completed edits.
- [x] Run relevant host/Node checks, rebuild Windows package, commit and push without starting CI.

No live Codex request may run without explicitly selecting gpt-6-luna by flag.

Evidence:
- Initial red: new recovery runner could not load before shared recovery methods existed.
- Shared recovery: 22 assertions pass from source and rebuilt PCK, including successful empty replies, cancellation, exhaustion, adapter death and Pi generation limits.
- Native recovery matrix: all 13 external adapters pass failure/retirement/exact-session-resume/transcript checks using executable protocol fixtures, without model requests.
- Complete Node suite passes (`node --test --test-reporter=dot tests/*.test.mjs`).
- Installed Pi against the local provider emulator: 140 passed, 0 failed. Its native retry tests intentionally disable outer recovery to verify both budgets independently.
- Windows launcher Go tests/build, PCK export, isolated package-content/recovery checks and structural package verification pass.
- Full 36-runner host suite passes uninterrupted (`gamesmith-tests-gPZ93o`), followed by the additional successful-empty-reply assertion in the focused source/package checks. Existing lifecycle runners disable outer retries so their terminal-failure assertions still test the native lifecycle layer.
- No live Codex model requests, paid provider calls or GitHub CI runs started.
