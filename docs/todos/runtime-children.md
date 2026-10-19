# Additive runtime children

- [x] Regress late insertion, constructor/property validation, stale targets,
  collisions, preflight failures, cancellation, changed code and owned removal.
- [x] Implement shared insertion and separate-process preflight; wire tools to
  every assembled harness and document the narrow guarantee.
- [x] Run focused source and packaged acceptance; rebuild Windows package.
- [x] Commit/push intended changes, preserving Brain.txt and unrelated files.

Scope: no script replacement, arbitrary node removal, rollback, snapshots or
automatic conflict detection. A passing preflight tests a fresh game, not the
exact live state. Live initialization can still fail after side effects.

Verification (2026-10-20):

- TDD red: `gamesmith-verify-IghaVL/results.json` rejected the initially unknown
  tool. The final dedicated runtime runner passes 35 assertions, including
  ready/deferred/process/physics failures, live-only side effects, cancellation,
  timeout cleanup, changed code, a name collision during preflight, fresh preload
  dependencies and actual OpenCode inherited bridge responses.
- Broad focused run: `gamesmith-verify-kc1ukL/results.json`, 518.964 s. Package
  build, source injection, all fourteen assembled tool catalogs, prompt contracts,
  reload preflight, property/output/runner contracts, cache/loading policy,
  bridge ownership, shutdown, OpenCode/Codex lifecycle, review Stop and packaged
  contents/structure passed. Both source and PCK execute isolated late insertion
  and owned removal without replacing the live parent.
- That run had two failed suites: detached process maintenance did not reach
  running before its wait deadline, and Command-code reload cleanup exited zero
  without confirmed graceful status. Do not describe the original run as green.
- Exact failed-suite rerun, unchanged code:
  `gamesmith-verify-zxDjBB/results.json`, 105.137 s; setup plus both suites pass,
  111 assertions, zero failures/skips/reuse. These failures did not reproduce;
  no production timeout or acceptance requirement was weakened.
- Evidence directories above are beneath
  `C:/Users/User/AppData/Local/Temp/`. Deterministic fixture/source/package tests;
  no real-provider invocation and no claim of Jopa 2 gameplay/visual validation.
  The user's live game, source and Brain.txt were left untouched.
