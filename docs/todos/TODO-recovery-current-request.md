# Current-request recovery

- [x] Reproduce loss of a later request before native admission, despite existing history.
- [x] Include the original objective and inspect-before-repeating instructions in every retry.
- [x] Track preservation per operation using native admission evidence; treat uncertain persistence conservatively.
- [x] Verify assembled adapters and shared host recovery, then run broader checks appropriate to the shared change.
- [x] Record results and limitations.

Do not infer current-request preservation from the existence of an older session. ACP updates without a turn identity are not proof of durable admission.

Initial regressions: AGY, Crush and Cline all reported `request_preserved:true` for rejected later requests; all three failed as expected before the fix. Focused host testing also caught OMP reporting completion before host admission, leaving the host waiting for its RPC response; rejection now returns the matching failure response.

Focused verification: assembled AGY/Crush/Cline/OMP adapter tests and shared recovery checks passed in the initial focused run; the native matrix initially exposed the OMP response bug above. After correction, `verify --rerun-failed` passed the native matrix, including later-turn objective delivery through actual IPC for AGY, Crush, Cline and OMP. The final release run below rechecks the changed OMP path and complete shared behavior.

Final command: `node tools/testing/verify.mjs --suite release --output errors --build-package`. No live paid-provider calls or GitHub CI dispatch.

Final evidence: `C:/Users/User/AppData/Local/Temp/gamesmith-verify-tGnKd7/results.json` — passed all 81 steps in one uninterrupted run (1077.6 seconds), with no failed, blocked, interrupted or reused steps. This includes all isolated host runners, rebuilt Windows package checks, Pi/local-provider emulator acceptance (140/140), migration (1/1), and windowed ownership (29/29). Shared recovery passed 52 assertions; the native recovery matrix passed 135.

The tested inputs stayed unchanged during the release run. This final evidence annotation was added afterward. These are local fixture/emulator results, not real-provider acceptance or remote CI. Conservative native-admission evidence does not guarantee exactly-once tool execution; retry instructions explicitly require inspecting existing work.
