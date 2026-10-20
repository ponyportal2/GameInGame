# ds merge fixes and final verification

- [x] Regress nested-link recursive deletion and advertised session selection.
- [x] Fix recursive unlinking and the shared runtime-log schema.
- [x] Pass focused regressions.
- [x] Rebuild Windows package and complete final full verification.
- [x] Merge into main, push, and verify remote revision.

Preserve unrelated Brain.txt and tools/fake-openai-endpoint.zip. No live provider
calls or GitHub CI are required. Keep inputs unchanged during verification.

Red: `%TEMP%/gamesmith-verify-O0NArI/results.json`, 2 passed / 2 failed.
Shared schema regressions failed for the fourteen harnesses; public recursive
deletion removed its outside sentinel. Public historical-session selection
already passed, confirming the mismatch is in the advertised schema.

First fixed run: `%TEMP%/gamesmith-verify-fbMAHc/results.json`, 3 passed / 1
failed. Both reviewed fixes passed (179 core assertions and all fourteen schema
consumers). Workflow failed its existing assumption that injection always
completes inside 300 ms; the actual grenade behavior passed. The fixture now
settles that same action ID, preserving smoke/survival assertions and separate
same-call fast-action coverage.

Failed-only rerun: `%TEMP%/gamesmith-verify-PrZ3MC/results.json`, 2/2 passed,
including 28 workflow assertions and historical-session selection. Next gate:
full suite with a fresh Windows package, unchanged inputs throughout the run.

Final full run: `%TEMP%/gamesmith-verify-8sM53J/results.json`, with
`--suite full --build-package --output summary`, jobs=4, 1447.2 seconds.
90 entries passed / 1 failed; no blocked, interrupted, reused or skipped entries.
Assertions: 4002 passed / 3 failed / 1 skipped. Windows package build,
package checks, launcher checks, both reviewed regressions and workflow passed.
The sole failing entry was `host:runtime_properties`: a private reload preflight
completed its smoke window and exited zero without a confirmed graceful-shutdown
status; the reload rejection caused three cascading assertions. It is not counted
as a passing full run.

Unchanged-code failed-only rerun:
`%TEMP%/gamesmith-verify-XeTYQM/results.json`, 2/2 entries passed,
164 assertions, 20.2 seconds. No smoke/shutdown safeguards were weakened.
The combined evidence covers the complete final code/package tree, with the
initial intermittent shutdown failure retained explicitly. All executions were
deterministic fixtures and real local Godot processes, with no provider calls.

Merged by fast-forward and pushed both `main` and `ds`; `git ls-remote`
confirmed both at `c2a387302f056ae35f16ed2e8b3a0cc94f98b3f1`.
This final checklist update changes documentation only.
