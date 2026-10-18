# Detached startup smoke checks

- [x] TDD: headless and windowed tests require completed smoke ticks before running.
- [x] Exercise process, physics and deferred failures in both modes; retain diagnostics.
- [x] Keep successful detached tests alive for inspection/input and normal Stop.
- [x] Focused source and packaged verification; rebuild, commit and push.

Reuse the existing smoke window. No new gameplay test language, input tools or
live mutation machinery.

Both modes retain `starting` until the shared smoke measurement completes at
least four process ticks and three physics ticks. `startup_smoke` in test status
and logs reports the completed counts, error count and pass/fail reason. Failure
exits with a nonzero code and retained diagnostics. Success enters `running` and
continues accepting the existing test controls; launch itself still returns
immediately. Clean shutdown remains a later Stop operation.

Verification (2026-10-18):

- TDD red: the new headless/windowed assertions failed on missing smoke evidence
  in `%TEMP%/gamesmith-verify-6NJhLP/host-test_process.log`. Stopped that run once
  the gap was established; no complete red-suite pass is claimed.
- Green: `node tools/testing/verify.mjs --test
  host:test_process,host:reload_preflight,host:chat_test_process,package:contents,package:structure
  --build-package --output errors` completed in 205.6 seconds. All seven entries
  passed; no failed, skipped, blocked, interrupted or reused entries.
- Evidence: `%TEMP%/gamesmith-verify-01QaOT/results.json` and individual logs.
  Detached-process fixture: 95 assertions, including actual headless and rendered
  processes, immediate process/physics/deferred error rejection in both modes,
  retained error evidence, continued controls/screenshots and normal Stop.
  Reload preflight: 40 assertions. Paused-chat bridge isolation: 16 assertions.
  Packaged checks exercise automatic detached startup smoke via the shipped PCK,
  reload rejection and live property inspection/mutation; package structure passes.
- Windows PCK rebuilt. No full-suite rerun, provider calls or CI dispatch.
