# Faster focused verification

- [x] TDD: exact affected-selection regressions and fail-safe unknown paths.
- [x] Separate shared prompt text; exercise actual prompt generators for all harnesses.
- [x] Audit and explicitly allow parallel-safe host runners; test barriers and job bounds.
- [x] Check representative selections and complete full serial validation.
- [x] Rebuild/check package and review diff.
- [x] Commit changes; verify remote revision as the final publication check.

Preserve product deadlines, recovery waits, native settings and evidence fingerprints.
Unknown code inputs continue to select full coverage. No dependency inference,
resource-lock framework or additional cache.

## Parallel audit

Only four host runners are allowlisted. All use the read-only imported project;
Godot import/build happens before them and package tests never overlap them.

| Runner | Writes and effects reviewed |
| --- | --- |
| runtime_node_lifecycle | In-memory SceneTree only; no files, CLI, ports or external processes. |
| runtime_properties | Fixtures/bridge files and generated-game Git state beneath isolated user://runtime-properties; engine state stays in its own process. Controllers dispatch fixture bridge requests without launching native agents. Reload coverage now starts isolated Godot preflight children; they read the project and write only beneath the runner's isolated user data, without fixed ports or shared artifacts. |
| harness_assembly | Reads catalog/module resources and writes only user://assembled. |
| prompt_contract | Reads production controllers; writes isolated game metadata and Pi module/prompt/config files under user://. No provider/native process is started. |

Everything else remains serial, including cache, native lifecycle, process,
package and approval/recovery suites. Safe runners finish before any serial
runner starts. The allowlist is deliberately small; selection is the main gain.

## Development evidence

- Selection regression failed first: a single runtime-properties test selected
  the entire inventory. It now selects itself plus node:verification.
- Scheduler regression failed first because no bounded host scheduler existed;
  then passed concurrency bounds, barriers, interruption and failed-result checks.
- Initial focused run: all host runners passed, including 811 prompt assertions,
  164 runtime property assertions, 17 lifecycle checks and 14 assemblies. The
  verifier fixture exposed exact reruns consulting unrelated affected paths;
  fixed by applying explicit selections without affected selection first.
- Failed-only rerun passed: `%TEMP%/gamesmith-verify-r4ICpl/results.json`.
- Updated prompt/native-tool contracts and verifier passed together:
  `%TEMP%/gamesmith-verify-dIpOba/results.json` (25.8 seconds).
- Shared prompt extraction preserves the original text after newline normalization.

Representative changed-path selections (full inventory: 84 tests): test-only 2;
prompt-only 3; runtime properties 4; Copilot controller 6. Exact IDs are asserted
or checked through the production selector; unknown production/framework files
still select full coverage.

- Full serial source/package run passed: 84 selected tests, 86 passing entries
  including setup/build, in 22m50s. Evidence:
  `%TEMP%/gamesmith-verify-u2q0Mf/results.json`. Package contents, structure and
  launcher checks passed. The existing opt-in Command-code provider subtest
  remained skipped because its explicit CLI environment was not configured.
- The second full run with four jobs was deliberately stopped after user feedback
  about excessive verification time. It is incomplete evidence; no full-suite
  parallel speedup or serial/parallel parity is claimed. Scheduler regressions
  validate bounded concurrency and serial barriers, not suite-wide timing.
- No real-provider acceptance or CI dispatch was performed. No product waits,
  global harness settings or running player games were changed.

## Completed parallel comparison

At the player's request, the full suite was subsequently run to completion on
`b539a38c53b2720192354801b124891ff0cbbaf7` with
`node tools/testing/verify.mjs --suite full --jobs 4 --output summary`.

| Result | Serial, jobs=1 | Parallel, jobs=4 |
| --- | --- | --- |
| Elapsed | 1,370.417 seconds (22m50s) | 1,102.673 seconds (18m23s) |
| Selected test IDs | 84 | Same 84, exact set comparison passed |
| Passing entries | 86, including package build | 85, using the rebuilt package |
| Passing assertions | 3,317 | 3,317 |
| Failed assertions | 0 | 0 |
| Opt-in skipped subtests | 1 | Same 1: Command-code native CLI not configured |

Observed saving: 267.744 seconds (4m28s), or 19.54%. The serial run included a
4.169-second package build. This is one comparison, not a stable performance
guarantee. Jobs=4 also parallelizes Node files, so the saving must not be credited
entirely to the four newly allowlisted hosts; summed host durations also differed
between runs. Full coverage intentionally bypasses affected-selection savings.

Parallel evidence: `%TEMP%/gamesmith-verify-0xbeOY/results.json`; comparison:
`%TEMP%/gamesmith-verify-0xbeOY/comparison.json`. Exit status was zero; all entries
passed, with no blocked, interrupted, reused or skipped entries and no input
invalidation. Source host checks, package contents/structure and launcher checks
all passed. No real-provider invocation was performed.

The earlier interrupted parallel attempt had completed tests through
`host:reload_settings` by 530.513 seconds without recorded failures. This later
completed run provides evidence that the parallel full-suite execution finishes;
the earlier interruption alone was not evidence of a stall.

## 2026-10-27: opt-in harnesses, hot-core mapping and crash fail-fast

Measured full run on this tree: 90 entries, 2,017.1 seconds wall with jobs=4;
host tests were 86% of the total. The fourteen lifecycle suites alone cost
533.0 seconds (24%), and one crashed runner consumed a 600-second deadline.

- Harness breadth is now explicit. `--suite core` keeps the reference harness
  (Pi); `--suite full` and its explicit alias `all` stay exhaustive, and
  `release` is the pre-release gate. An affected change that names a harness
  still selects that harness, and a changed shared module or inherited
  controller still selects every consumer. `--suite host` and `--suite node`
  stayed complete phase selections: `run-host-tests.mjs` calls `--suite host`,
  and a compatibility entry point must not silently drop the opt-in harnesses.
  An unmapped path is exhaustive too. Printing the narrowed fallback did not
  make it safe: an unknown shared file can change behavior in any harness, and
  a run that never executes that harness still reports green.
- `src/core/game_runner.gd` and `src/core/game_tools.gd` are audited in
  `INPUT_CONSUMERS` by behavior, not by preload count: direct preloads plus the
  suites that drive the run/reload path or call the tool facade and assert on the
  result. A core edit now selects 17 and 13 tests instead of the whole inventory.
  Suites that only start a game as scaffolding for another subject stay out; they
  still run in `full`, `all` and `release`.
- A `SCRIPT ERROR` whose innermost frame is under `res://src/` or `res://tests/`
  proves the runner coroutine died before `quit()`. The verifier kills that test
  immediately. Parse errors in generated candidates under `user://` remain
  expected and do not trigger the kill.
- `runtime_properties_runner.gd` now exits after a failed fixture load instead of
  continuing into a null game and hanging until the deadline.
- `JsonStore._replace_file` retries only on Windows, where a reader holding the
  destination open actually blocks a replacement, and returns the last error
  instead of a fixed one. The test child falls back to a direct final status
  write and reports it if that also fails. A supervisor polling `status.json`
  could turn a graceful stop into `cleanup_failed`; that was the remaining
  source of the preflight flake.
- A cancelled operation skips the second workspace fingerprint, in the
  verifier and in `GameRunner.checked_reload()` /
  `GameTools._checked_runtime_child()`: nothing will be loaded, so the check only
  delays the caller. A second fingerprint that fails is `fingerprint_failed`,
  not `code_changed`, which claimed an edit nobody observed.
- The fail-fast immediately exposed a real race in `reliability_runner.gd`:
  approval responses are written only after the reload coroutine resumes, so the
  suite read `response-*.json` before it existed and crashed on `null.ok`. It now
  waits for each response, and that wait (30 s) outlasts the 15-second preflight
  it is waiting on instead of failing a slow preflight as a suite error.

### Evidence for the `core`/`full` split

- Selector unit regressions: `node --test tests/verification.test.mjs` 11/11.
- `--changed src/core/game_tools.gd`: 13 tests, 15 entries, passed in 570.1 s.
- `--changed src/core/game_runner.gd`: 17 tests, 19 entries, passed in 548.4 s.
- `--suite full` parity after the split: 91 entries (89 tests, package build and
  Godot setup), 0 failed, 1,544.2 s. The exhaustive request still runs everything.
- Selections after the follow-up: `core` 48, `full`/`all` 89, `release` 92,
  `host` 47, `node` 39, `package` 2, `launcher` 1. `--suite host` contains all
  thirteen non-Pi harness host suites, so `run-host-tests.mjs` still runs
  everything it used to.
- `--since main` was proved end to end on a scratch branch whose only change was
  already committed, so `git diff HEAD` was empty: the SoftFac command
  `--suite affected --since main` selected `node:verification`, ran it, and failed
  a deliberate red assertion with exit code 1. A committed branch is no longer a
  vacuous green.

An unmapped path now selects every test, including `src/ui/app.gd` and
`tools/testing/assembled-runtime.mjs`, so an unknown shared file can no longer
pass SoftFac without the harness that depends on it. Untracked files are still
inputs: a local scratch file must be ignored (it lives in `.git/info/exclude`
here) or moved out of the repository, rather than making unknown code cheaper.

## 2026-10-28: per-harness recovery, controller base, workspace operations

Three boundaries were separated without changing behavior. Evidence is one
focused run per boundary plus a single exhaustive pass over the completed set;
the exhaustive pass is the only run that executes every scenario.

- **Recovery scenarios.** `native_recovery_runner.gd` keeps one shared
  implementation and takes the harness as `-- <id>`. `allTests()` registers
  thirteen `host:native_recovery_<harness>` entries that share the file, and the
  affected selector collects every entry for a shared source instead of only the
  first. `verify.mjs` forwards an entry's arguments to the runner. A harness
  suite now runs one scenario (13.6 s for Copilot), while
  `--changed tests/native_recovery_runner.gd` still selects all thirteen.
- **Controllers.** `AgentControllerBase` owns the signals, host bridge, recovery
  loop, editor guard and shared state; `PiAgentController` keeps only the Pi
  transport. The twelve native controllers call `game_prompt.gd` directly
  instead of obtaining the prompt through the Pi config. Pi request completion
  and stale settlement moved to `host:pi_controller`; `host:turn_recovery`
  became a shared harness test because it now drives inherited behavior.
- **Pi selection.** Pi is no longer a parent controller, so it left the
  hard-coded inherited-controller escalation. Its `INPUT_CONSUMERS` entry is
  audited by behavior: every suite that instantiates the Pi controller
  (`pi_controller`, `turn_recovery`, `reliability`, `harness`, `bridge_claim`,
  `chat_test_process`, `maintenance`, `test_process`, `prompt_contract`) plus
  the app suites that drive the default agent (`test`, `library_actions`,
  `reload_settings`, `ui_layout`, `blender`, `review_stop`, `chat_history`).
  `agent_controller_base.gd` stays unmapped and therefore exhaustive.
- **Workspace operations.** `WorkspaceOps` owns list/read/search/write/patch/
  move/delete plus the containment, link and `.git` rules. `GameTools` keeps a
  settable `workspace` that forwards to it, so renaming a game rebinds the
  boundary through the existing assignment and the facade stays the call site
  for controllers and fixtures. `host:workspace_ops` holds the component
  boundary, junction and large-file tests plus one small facade scenario that
  drives `execute()` dispatch, paginated read/patch, boundary rejection,
  move/delete and operations after rebinding over real files. `host:test` left
  the `game_tools.gd` consumer list because the moved tests were its only use
  of the facade; `host:workspace_ops` is selected for both files. Suites that
  write fixtures through the facade without asserting on the boundary
  (`blender_integration`, `pi_integration`) gain nothing from a narrower
  selection and still run in `full`, `all` and `release`.

Selections after the batch: `core` 49, `full`/`all` 103, `host` 61,
`node` 39, `release` 106, `pi` 10, `copilot` 7. A change to
`workspace_ops.gd` selects six tests, `game_tools.gd` thirteen and
`pi_agent_controller.gd` seventeen; `agent_controller_base.gd` still selects
all 103.

- Selector regressions: `node --test tests/verification.test.mjs` 11/11 (6.4 s),
  including the Pi narrowing and the base-controller exhaustiveness assertions.
- `--test host:turn_recovery,host:pi_controller`: 3 passed, 7.8 s.
- `--test host:test,host:copilot_lifecycle,host:command_code_compaction`:
  4 passed, 88.4 s.
- `--test host:blender`: 2 passed, 35.6 s.
- `--test host:workspace_ops,host:test,host:reliability`: 4 entries passed in
  115.2 s, with 62, 116 and 99 assertions respectively.
- `--changed src/core/workspace_ops.gd`: the full six-test selection
  (`workspace_ops`, `runtime_properties`, `reliability`, `blender`,
  `package:contents`, `node:verification`) passed in 192.7 s with 522
  assertions and a package rebuild. The focused component suite alone is 0.76 s
  and 82 assertions and constructs no app, runner or Git repository.
- `--changed src/agent/pi_agent_controller.gd`: the seventeen-test selection
  passed in 386.5 s with 2,687 assertions, versus 103 tests and 1,556.7 s for
  the exhaustive pass.
- `--check-only` parsed the base controller, Pi, all twelve native controllers
  and the affected runners.
- `--suite full` on this tree: 103 selected tests, 105 entries including the
  package build and Godot setup, 4,188 assertions passed, 0 failed, 1 skipped
  (the opt-in Command-code native CLI), 1,556.7 s at jobs=4. Evidence:
  `%TEMP%/gamesmith-verify-YTfCn5/results.json`. The tracked `.pck` was rebuilt
  by that run.

Affected-run evidence: `%TEMP%/gamesmith-verify-gmiz4Y/results.json` (workspace
operations) and `%TEMP%/gamesmith-verify-nGCUoS/results.json` (Pi transport).

