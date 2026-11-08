# Voice runtime packaging and repair

- [x] Regress clean Windows folder assembly with all canonical voice licenses.
- [x] Regress explicit Install repairing a missing Python DLL and corrupt pip wheel.
- [x] Copy canonical licenses during assembly and refresh the runtime on explicit Install.
- [x] Run focused source and rebuilt-package checks; record results.
- [x] Commit and push to main; verify remote revision at delivery.

Scope: keep normal runtime reuse; explicit Install restores bundled files before
reinstalling packages. Preserve models. No startup probes or new repair framework.

## TDD

`%TEMP%/gamesmith-verify-ITFQHA/results.json`: both new regressions failed before
the fix. Clean assembly failed the production package verifier for missing
licenses; public Install retained both damaged runtime files despite a matching
ready marker. Existing runtime/IPC checks passed. No downloads/provider calls.

## Verification (2026-11-08)

- Exact failed-only rerun: `%TEMP%/gamesmith-verify-1cjDab/results.json`, 3/3
  entries passed after the fixes.
- Final focused run: `%TEMP%/gamesmith-verify-xVG8B3/results.json`, 9 selected /
  11 entries, 171 reported assertions, no failures/skips/reused evidence, 117s.
  Includes 16 underlying Python cases via `node:voice`, verifier/Pi contracts,
  source runtime (12), voice UI (62), picture UI (29), layout (30), and rebuilt
  package structure/contents. The clean-assembly regression executes the actual
  workflow Bash step in a temporary workspace with structural binary fixtures,
  then checks every canonical license byte-for-byte; no remote CI was dispatched.
- Actual rebuilt PCK runtime: 12/12 assertions, exit 0, including both damaged
  file repairs through public Install, preserved model sentinels, interpreter/
  pip execution, silent-audio IPC and worker shutdown. Evidence:
  `%TEMP%/gamesmith-voice-repair-pck-ba71c822a01d40eb87c3d9e0c5988863/runtime.log`.
  The fixture stops Install after extraction, before package downloads; this
  patch did not repeat real dependency installation or speech-model inference.
- Final tested PCK SHA-256:
  `e52ede9edb207a4706560c0514ea83642432b233783c104aacfaee42cc71cf8a`.

No exhaustive suite, real provider calls, microphone recording or model downloads.

## Follow-up: installation readiness

- [x] Regress valid, absent, mismatched and restored runtime readiness with existing recognition markers/packages.
- [x] Require matching readiness in `installed()`; leave repair behavior unchanged.
- [x] Verify source, rebuilt package and PCK runtime; record evidence and push.

### Follow-up verification (2026-11-08)

- TDD red: `%TEMP%/gamesmith-verify-hb5iMM/results.json`; missing and mismatched
  readiness incorrectly reported installed, while both positive controls passed.
- Exact failed-only rerun: `%TEMP%/gamesmith-verify-E7s09g/results.json`, 2/2
  entries passed after adding the readiness requirement.
- `--suite affected --since main`: `%TEMP%/gamesmith-verify-xwkSeu/results.json`,
  7 selected / 9 entries, 172 reported assertions, no failures/skips/reused
  evidence, 114.6s. Includes source runtime, voice/picture UI, layout, deterministic
  worker/assembly cases, verifier contracts and rebuilt PCK contents.
- Actual PCK execution: 16/16 runtime assertions, exit 0; readiness positive and
  negative cases, runtime repair, interpreter/pip execution and worker IPC/cleanup.
  `%TEMP%/gamesmith-voice-ready-pck-de8d1184d58948cdbc5dcdf390385ec3/runtime.log`.
- Follow-up tested PCK SHA-256:
  `101b72d0e661b817ce51845868a1d9920b9d3e914b5b80e287691b7c975e2d57`.

No provider calls, package/model downloads or microphone/speech inference; package
presence in the readiness regression is a fixture, not real recognition imports.
