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

