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
