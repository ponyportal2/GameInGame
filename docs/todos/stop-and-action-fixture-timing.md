# Stop and action fixtures: wait for the work instead of the clock

Status: done (2026-10-20)

The `affected` suite run on a loaded machine surfaced three flakes. All three
were tests measuring the wrong moment, not product regressions.

## 1. Codex and Cline Stop

`host:codex_lifecycle` failed `Codex Stop kills adapter and backend for SETTLE`
and `host:cline_lifecycle` failed
`Cline Stop force-retires a stuck backend: GAMESMITH_CLINE_STUCK_CANCEL`.

Both runners slept 0.6–0.7 s after `send_player_request` and then pressed Stop.
When the fixture had not yet accepted the request, the adapter had nothing stuck
to cancel, `cancel()` returned quickly, the healthy runtime stayed alive, and
the test failed an assertion that the process was dead.

- `fake-codex.mjs` writes `.codex-fixture-busy.json` when it accepts
  `initialize` under `GAMESMITH_CODEX_STUCK_START` and in `turn/start`.
- `fake-cline.mjs` writes `.cline-fixture-busy.json` for the same two cases.
- Both runners delete the marker, send the request, and wait for it (bounded to
  8 s) before pressing Stop. The Codex runner also polls for process death
  (`wait_dead`, 3 s) and measures the grace bound before polling.

## 2. Packaged test actions

`package:contents` failed `packaged detached injection/mouse/completion` with
`{"ok": true, "pending": true}` followed by
`A test action is already pending.`

`_service_pending_test_commands` answers `pending` after 300 ms so a slow action
never blocks the bridge; the agent is expected to poll the returned `action_id`.
The runner treated the first answer as final, which only holds on an idle
machine.

`_bridge_action` now polls with the returned `action_id` (50 ms apart, 15 s
budget) exactly like the agent, so the assertion checks the finished action on
any machine.

## 3. The same signature again (2026-10-28)

The SoftFac gate hit it once more, on a loaded machine. Two holes remained:

- The poll bound was attempts-based (`attempts < 200` at 50 ms), and on timeout
  `_bridge_action` returned the still-`pending` answer. The runner then
  dispatched the next action, which the supervisor rejected with
  `A test action is already pending.` — blaming the action after the one that
  actually stalled.
- The runner discarded the `release` result, so a stall in `press` only showed
  up two calls later.

`_bridge_action` now polls to the deadline and returns
`{"ok": false, "timed_out": true, "action_id": ...}` naming the action, and the
runner asserts `release` like the others.

## Evidence

```
node tools/testing/verify.mjs --test host:codex_lifecycle,host:cline_lifecycle --output summary
PASSED: {"passed":3,"failed":0,...}; 138.0s

node tools/testing/verify.mjs --suite package --output summary
PASSED: {"passed":4,"failed":0,...}; 99.3s
```

Note: `--build-package` inside a verification run rewrites the tracked
`GameSmith.pck`, which trips the runner's own input fingerprint
(`Inputs changed during verification`). Build first, then verify:

```
node tools/testing/verify.mjs --suite package --output summary --build-package   # rebuild only
node tools/testing/verify.mjs --suite package --output summary                   # clean evidence
```
