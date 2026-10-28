# OpenCode harness

- [x] Write failing protocol, workspace/tool-policy, and harness UI regressions.
- [x] Implement headless adapter, native MCP bridge, persistent per-game sessions, and cancellation.
- [x] Add harness selection and disable unsupported model/compaction controls while preserving settings.
- [x] Verify deterministic lifecycle and real installed OpenCode editing/testing/resume.
- [x] Document, rebuild and verify Windows package.
- [x] Commit and push.

Verification: 11 Node adapter tests and Windows bootstrap Go tests pass. Host suites pass through the harness/lifecycle group (rerun together after fixing test settings leakage). Native OpenCode 1.19.0 on the installed free model created and headlessly tested a game, resumed the same conversation, and retained pending reload approval beyond 65 seconds. Cancellation regressions verify both CLI and MCP descendants stop; failed reload diagnostics allow repair in the same request. Rebuilt Windows launcher/PCK pass package checks; exported chooser/settings test passes. Restart the running app to load the updated package.

OpenCode 2 (2026-10-29): v1 is no longer installed, so the adapter moved from the
`opencode serve` HTTP/SSE API to the native `opencode acp` stdio backend. The
confined `build` agent is written as OpenCode 2's ordered permission-rule list
(default deny, native read/glob/grep/edit/write/skill, GameSmith MCP, reserved
`.git` denies last); sessions use `session/new` and `session/load`, the mode is
pinned to `build` after load, Stop sends `session/cancel`, and Kilo keeps the
shared HTTP/SSE transport. Node regressions: `tests/opencode*.test.mjs` pass.
Live acceptance on installed `opencode 2.1.2`:
`node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe opencode_integration_runner.gd`
returned `{"passed":9,"failed":0}` in 113.1s (evidence
`%TEMP%/gamesmith-verify-jAP6M4/results.json`).

Context accounting (2026-10-29): the v2 worker used `session/prompt`'s
`usage.totalTokens` as a fallback whenever a turn did not raise the measured
context count. That number is the call's consumption (prompt + completion), not
the occupancy of the session, so a turn that merely added 120 tokens could
overwrite a real 5120 reading, and a turn with no `usage_update` at all
reported a bogus occupancy instead of "unknown". `tools/opencode/worker.mjs`
now takes the count only from `usage_update.used`; a repeated measurement is
kept as-is and a missing one leaves the stored count untouched.
`tools/testing/fake-opencode.mjs` had masked this by returning 5120 for both
measurements; it now reports occupancy 5120 separately from consumption 120 and
can omit the update (`context-missing`). Two regressions in
`tests/opencode-server.test.mjs` cover the unchanged measurement and the missing
update; both fail against the old worker (observed `[5120,5120,120]` and a
non-null persisted count) and pass now. `tests/opencode*.test.mjs`: 20/20.
