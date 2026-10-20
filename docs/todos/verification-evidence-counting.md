# Host failure assertion counts

- [x] Count Godot `ERROR: FAIL:` lines as failed assertions.
- [x] Point failure excerpts at the first real host failure.
- [x] Unit coverage for both helpers.

## Problem

Host runners report failures through `push_error("FAIL: ...")`, which Godot
writes as `ERROR: FAIL: ...`. `assertionCounts` only matched a line-initial
`FAIL:`, so a failed host run recorded `assertions.failed: 0` in `results.json`
while the entry status correctly failed. `failureExcerpt` did not recognize the
prefix either, so `--output errors` showed the tail of the log instead of the
first failure.

## Verification (2026-10-20)

- RED: `node --test --test-name-pattern="host failures" tests/verification.test.mjs`
  failed (`# fail 1`) against the previous helpers.
- GREEN: the same selection passed (`# pass 1`) after the change, and the full
  `tests/verification.test.mjs` file passed 10/10 in 18.6 seconds.

Limitations: a runner that both prints `FAIL:` and pushes `FAIL:` for the same
assertion would be counted twice; current runners use one form per assertion.
No host or package suite was rerun for this tooling-only change.
