# Live runtime inspection and property mutation

- [x] Write and run failing runtime and assembled-harness regressions.
- [x] Implement bounded inspection and explicit batch property writes beneath active_game.
- [x] Wire all harnesses and update iteration instructions.
- [x] Run focused regressions, full shared-consumer coverage, and package acceptance.
- [x] Review diff and prepare intended changes for delivery.

Scope: no script reload, node replacement, state migration, or expression evaluation.
Evidence and limitations will be recorded here as verification completes.

Initial red: `gamesmith-verify-Rf3woG/results.json` failed on missing inspection;
`gamesmith-verify-ZN6cF5/results.json` failed on missing harness registration;
`gamesmith-verify-tpRkG1/results.json` failed on untyped fields and bridge dispatch;
`gamesmith-verify-KnCDHH/results.json` failed on queued ancestors and prompt guidance.
Focused green: `gamesmith-verify-NFUKWo/results.json` (4/4 entries; 77 runtime
assertions, 14 assembled harness registrations, OpenCode MCP coverage).
Existing Blender process-ownership test required execution outside the sandbox;
its isolated rerun passed (`gamesmith-verify-qvCppf/results.json`).

Full source/package regression run: `gamesmith-verify-09krgo/results.json`;
82 entries passed, one stale OMP tool-count assertion failed (19 expected,
21 actual after adding the two tools). Corrected the assertion and checked the
new tool names; `--rerun-failed` passed both entries and all 16 OMP assertions
outside the sandbox (`gamesmith-verify-jUbkQP/results.json`).
An intervening sandbox rerun (`gamesmith-verify-sjRXwn/results.json`) was stopped
after its native-backend-death test could not terminate the fixture backend;
it is not passing evidence. The same check passed outside the sandbox.

Final wording and expanded value/rename regressions, with a fresh PCK build:
`gamesmith-verify-ucDnOj/results.json` passed 9/9 entries, 139 assertions.
This includes 89 runtime assertions, all 14 canonically assembled harness
registrations, Command-code/OpenCode/Pi registration consumers, and packaged
live inspection/mutation plus package structure. No inputs changed during
these verification runs. `git diff --check` passed.

No real-provider calls or visual gameplay acceptance were performed. The full
suite's opt-in Command-code native ACP test was skipped. The package was rebuilt;
an already-running application was not restarted.

Runtime patches are temporary and do not update loaded script defaults for
future spawns. A regression proves source edits remain unapplied to those
spawns until reload. Agent instructions explain live spawner configuration or
reload as the fallback. Persistent source edits remain required.

Delivery: commit the reviewed implementation and rebuilt package, push main,
and verify the remote revision; report that revision in the final response.
