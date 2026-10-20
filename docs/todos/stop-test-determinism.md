# Stop tests: wait for an in-flight turn

Status: done (2026-10-20)

## Problem

`host:review_stop` and `host:kilo_stop` failed intermittently on Windows with

```
PASS: Stop settles stalled SETTLE
PASS: Stop grace bounds SETTLE
FAIL: Stop kills blocked adapter SETTLE
FAIL: forced Stop kills backend and MCP SETTLE
```

Both runners slept a fixed 0.6 s after `send_player_request` and then pressed
Stop. When the fixture had not yet reached its prompt handler, the worker's
`cancel` handler saw `active === undefined`, returned `{success: true}` in under
200 ms, and the controller correctly kept the healthy runtime alive. The test
then asserted that the adapter had been killed, so it failed on a correct
behaviour.

The controller side was verified with temporary instrumentation: `cancel`
logged `elapsed=139` and the worker logged `abort done` / `operation settled`
immediately, while the START and ABORT modes took the 5 s grace path and killed
the tree.

## Fix

- `tools/testing/fake-opencode.mjs` and `tools/testing/fake-kilo.mjs` write a
  `<harness>-fixture-busy.json` marker as the first statement of `run(prompt)`,
  so a test can observe that the turn actually started.
- Both stop runners remove the marker, send the request, and wait for the
  marker (bounded to 5 s) instead of sleeping 0.6 s.
- The grace bound is now measured when the busy loop exits, before any
  post-kill wait, so waiting for termination cannot consume the grace budget.
- Process death is polled for up to 3 s (`wait_dead_os` / `wait_dead`) instead
  of assuming a fixed 0.2 s is enough for `taskkill` to reap descendants.

## Evidence

`node tools/testing/verify.mjs --test host:review_stop,host:kilo_stop --output summary`

```
PASSED: {"passed":3,"failed":0,...}; 84.3s
host:review_stop passed {"passed":15,"failed":0}
host:kilo_stop   passed {"passed":15,"failed":0}
```

Before the change the same suites reported 13 passed / 2 failed each.
