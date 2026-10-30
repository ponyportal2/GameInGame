# OpenCode reset and verification follow-ups

- [x] Regress stale-session recovery through the existing Settings confirmation, provider isolation, and rejected resets.
- [x] Implement explicit OpenCode reference reset and enable its existing UI capability.
- [x] Select Pi-pin checks for the four authoritative Markdown files; keep unrelated Markdown ignored.
- [x] Suppress Cline updates during version probing and preserve the caller environment.
- [x] Run focused regressions, final affected verification, and rebuilt package checks. Record failures and reruns separately.

Scope: no automatic history discard, shared reset service, transport changes, provider calls, or CI dispatch.

## Focused evidence

- Before production edits, both new Node regressions failed and `host:native_reset` reproduced the missing reset. The first lifecycle attempt also exposed an incorrect test-only chat accessor, corrected to the real `chat_history` API.
- `gamesmith-verify-YDQKt6`: lifecycle recovery passed (26 assertions); reset had one overstrict fixture assertion (it expected ownership acquisition not to allocate a guard when denied).
- Corrected that assertion to require no acquired ownership and unchanged native runtime. Exact failed-only rerun `gamesmith-verify-MJiweF`: setup and reset passed, 28 assertions.
- Strengthened recovery to restart the adapter and prove the newly created reference is resumed. `gamesmith-verify-pXOjy5`: setup, full verifier contracts, Pi-pin contract, and OpenCode lifecycle passed (4 entries, 57.7 seconds).
- Generated harness inventory check passed. Final affected verification and rebuilt/package execution follow with frozen inputs.

## Final evidence

- Command: `node tools/testing/verify.mjs --suite affected --since main --output summary --jobs 4`.
- The inherited OpenCode controller and verifier infrastructure deliberately select the full deterministic inventory: 106 selected tests, 108 entries including package build/import. All 108 entries passed on the first final run, with 4,298 passing assertions, zero failures, and no reused results. One internal opt-in installed Command-code ACP acceptance check was skipped; no provider calls or installed-CLI acceptance were requested.
- Duration: 1,220.5 seconds (20m20s). No input-change or fingerprint errors. Results: `C:/Users/User/AppData/Local/Temp/gamesmith-verify-54RiCr/results.json`.
- The run rebuilt and verified the working-tree PCK, checked package structure/contents, exercised all native lifecycle/recovery consumers, and ran launcher unit tests.
- Separate packaged execution: `native_reset_runner.gd` loaded from `--main-pack` in isolated application data passed 28/28 assertions. Results: `C:/Users/User/AppData/Local/Temp/gamesmith-packaged-reset-MrhqPr/results.json`.
- Directly tested PCK SHA-256: `6e6997317547ae6b718ac187f856425b74e9fc2dc46a37fdd0d2728ef6f1c259`.
- `git diff --check` passed. Only this evidence note was updated after validation; executable and test inputs remain as tested. Delivery includes the same tested PCK. No CI was dispatched.
