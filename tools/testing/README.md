# GameSmith verification workflow

The default is a compact, portable verification command:

```powershell
node tools/testing/verify.mjs --suite affected
node tools/testing/verify.mjs --suite affected --since main --list
node tools/testing/verify.mjs --suite full --output summary
node tools/testing/verify.mjs --suite copilot --output errors
node tools/testing/verify.mjs --suite release --output full
node tools/testing/verify.mjs --rerun-failed C:/path/to/results.json
node tools/testing/verify.mjs --suite full --reuse C:/path/to/results.json
```

`--list` prints the selected test IDs, sorted one per line, without running tests or creating artifacts. It honors the normal selection options, including `--suite`, `--changed`, `--since`, `--test`, and `--rerun-failed`.

`summary`, `errors`, and `full` execute the same selection and save the same complete evidence. Summary prints phases, failures, infrequent long-running notices and the final result. Errors adds bounded failure excerpts. Full streams child stdout/stderr. Expected `ERROR` diagnostics never determine pass/fail: child exit status and deadlines do. Failed entries link a bounded diagnostic JSON and full log. `results.json` is authoritative; atomic `progress.json` is only for checking an apparent stall. No continuous polling is needed.

## Timing summary

At the end of each run, the verifier prints a header in this form:

```text
Timing: <suite>, <n> selected, <n> entries; wall … (build …, setup …, tests …)
```

`selected` is the number of tests chosen; `entries` is the number of result entries, including build/setup entries. `wall` is total elapsed time; `build` and `setup` are the recorded durations for those entries; `tests` is the remaining wall time after subtracting build and setup.

`Slowest:` ranks up to five executed test entries by duration. It includes only entries that ended `passed` or `failed` (not build/setup entries); reused and skipped entries never contribute, so timings from earlier runs cannot appear as stale rankings.

`--report <results.json>` reprints the same summary from saved evidence without running anything:

```bash
node tools/testing/verify.mjs --report C:/path/to/results.json
```

`--rerun-failed` normally selects failed, interrupted or blocked tests. If the prior run reports `inputs_changed`, it reruns the entire original selection because that evidence was invalidated, even if every child test passed.

Each run gets a new temporary artifact directory (printed at completion), or use `--artifacts <new-directory>`. All child logs, Godot engine logs and isolated application data remain available. `--jobs 4` bounds parallel Node files and explicitly audited host runners (`PARALLEL_SAFE_HOSTS` in `verification-plan.mjs`). Those host runners use separate application data and do not overlap serial runners. Package, native lifecycle and process suites stay serial; separate user data alone does not qualify a test for concurrency. `--jobs 1` provides a serial comparison. `--timeout <milliseconds>` is a test deadline, never a product/model timeout. A Godot script error inside the host project aborts the runner's coroutine, so the verifier kills that test immediately instead of waiting for the deadline; generated candidates under `user://` may fail parsing without being treated as a crash. Missing tools and setup failures fail the verification instead of quietly skipping required tests.

`--since <ref>` adds `<ref>...HEAD` to the changed paths, so a branch whose work is already committed still selects what it changed. Uncommitted and untracked files are always included; use it for a clean CI or factory checkout. A bad ref fails instead of selecting nothing.

Suites:

- `smoke`: orchestration, canonical assembly, core host and library checks.
- `affected`: explicit conservative path mapping in `verification-plan.mjs`. Known test-file changes select that test plus runner contracts; Test `.gd.uid` files follow their test source; explicitly mapped source UIDs follow the same map. `INPUT_CONSUMERS` enumerates audited shared inputs, including the hot core runner/tool files whose consumers were audited by behavior (preloads plus suites that drive the run/reload path or assert on tool-facade results). Harness-local changes select its protocol/lifecycle tests plus shared ownership/recovery/assembly coverage. Shared runtime modules select every inventory consumer. Pi and Command-code are concrete controllers with audited consumer lists; Command-code retains its UI/session-reset, approval, compaction and recovery integration tests. Changes to `AgentControllerBase`, `NativeAgentController`, inherited OpenCode or Cline controllers, verification infrastructure, and unknown code/fixture paths select every test: an unmapped shared file can change behavior in any harness, so a narrower guess could pass without the suite that would have caught it. The four Markdown Pi-pin authorities (root/testing README and root/Windows THIRD_PARTY_NOTICES) select only `node:pi-pin`; other documentation-only changes select none. Missing mapped consumers fail instead of silently reducing coverage.
- `<harness>`: harness Node suites, lifecycle, harness switching, shared native recovery and assembly.
- `core`: the intentionally narrowed everyday surface: core Node files, isolated host runners, PCK contents/structure and Go launcher tests, limited to the reference harness (Pi). No paid model calls.
- `full`: every discovered deterministic test, including all fourteen harness suites.
- `all`: the explicit name for the same exhaustive request as `full`. Each lifecycle suite costs roughly 40-50 seconds, which is why ordinary runs stop at `core`.
- `acceptance`: installed Pi against the local provider emulator, process-level data migration and windowed input ownership. Windowed coverage is explicitly skipped only if Linux has neither a display nor `xvfb-run`.
- `node`, `host`, `package`, `launcher`: complete phase selections, every harness included. `run-host-tests.mjs` calls `--suite host`, so these stay exhaustive rather than following `core`.
- `release`: `all` plus acceptance. It requires installed pinned Pi, Godot, Python and Go. This is the deliberate pre-release gate, so it keeps every harness.

`--test host:copilot_lifecycle,node:copilot-server` selects exact IDs. `--rerun-failed` selects only failed/interrupted/blocked entries from an earlier result, including children blocked by import failure; build failure also repeats the build. Fixes are allowed before a rerun. This is new evidence for that selection, not a claim that the old full run passed.

`--test acceptance:opencode-permissions` explicitly runs the installed OpenCode 2.1.2 CLI with the production assembled adapter and a deterministic localhost provider. It exercises native read/write/edit/search confinement, Windows junctions (symlinks elsewhere), repository metadata, resumed agent selection, and refusal when the workspace guard fails to load. It isolates native configuration/data and uses no provider account. This optional native acceptance is separate from the fixture-only `full` suite and requires the supported OpenCode CLI to be installed.

The PCK is rebuilt automatically whenever `package:contents` is selected. The export preset packs `src/`, `tools/` and `project.godot`, so enumerating packed sources here would just be another stale boundary; a rebuild costs less than a package test that silently verifies older bytes. Development tests run against these rebuilt working-tree bytes without requiring a commit. Any affected change to a packed file selects `package:contents`, even when its audited consumers are narrower.

For final delivery, `--require-committed-package` adds a separate check **after** the selected tests: the PCK must match HEAD, since the factory merges commits rather than working-tree files. SoftFac enables this gate; ordinary development runs do not. The gate runs even without an export, is never reused, and remains required by failed-only reruns of gated evidence. Commit the tested package before final delivery.

Reuse is opt-in and recorded per test as `status: "reused"` with `evidence_from`. It requires matching HEAD, working-tree content, suite definition, runtime identities and hashed environment knobs, plus existing complete logs. Changes during execution invalidate the run. Builds, live calls and acceptance are never reused. Runtime fingerprints include Node/platform, the Godot binary, Python/Go when needed, and installed Blender identity. Avoid editing sources while verification runs. No secret environment values are written to results.

Use `affected` for development and deliberately choose `full` or `release` for broader milestones. Selection precision does not weaken fingerprints: they still cover all repository inputs. Shared wording lives in `src/agent/game_prompt.gd`; its focused selection runs `prompt_contract_runner.gd` through all fourteen production prompt generators (with Blender enabled/disabled), canonical assembly and runner/catalog contracts. Configuration changes in `pi_runtime_config.gd` retain full coverage because that file also configures providers, credentials and sessions. Prompt contracts assert semantic clauses, not a second prompt or an exact-text snapshot. Product waits, retry backoff and timeouts are unchanged.

`--godot <executable>` or `GODOT_BIN` selects Godot; Windows defaults to the bundled executable. `--build-package` refreshes the PCK before testing. Live native inference is separate and explicit: `--live copilot`, for example. Codex live acceptance refuses to start unless `GAMESMITH_CODEX_BIN` points at `tools/testing/codex-luna-launcher.mjs`, which supplies the required explicit `-c model="gpt-6-luna"` override. No CI is dispatched by these commands.

The compatibility entrypoints `run-host-tests.mjs` and `run-verification.sh` delegate to this runner; `GAMESMITH_VERIFY_OUTPUT` controls their output mode. The manual Windows workflow uses the same release selection and uploads its complete artifact directory. Automatic CI remains disabled.

## Harness inventory and runtime parity

`tools/agent/harnesses.json` owns display labels, controllers, reset/settings capabilities, native module maps, launcher identities and focused suite membership. It is data, not permission policy. Native security/admission tests remain independent.

`HarnessInventory.assemble_runtime()` is the single module materialization implementation. Production controllers use it; Node fixtures invoke it through a small Godot adapter and execute the resulting tree; PCK checks assemble every harness from the exported resources. Tests no longer parse controller source or maintain their own copies of production assembly lists. Source-only `session-state.mjs` re-exports preserve direct worker compatibility; assembled runtimes contain the shared implementation itself.

After updating launcher metadata, run `node tools/testing/generate-harness-inventory.mjs`. The generator also derives the export include filter from the same module sources. A regression verifies both match the JSON. Harness-specific executable identity probes remain independent. Shared ACP code is limited to atomic session persistence and standard failure records; permission, resume, settlement and Stop semantics remain in each native adapter.

The usual host tests also cover standalone process ownership, hung-action polling, graceful/forced stop, test-storage retention and safe recovery, plus compaction failure backoff and unknown checkpoint usage. Real Pi verifies automatic compaction resumes unfinished tool work without another player message. On Linux, rendered tests require `xvfb-run` or a display.

The usual host tests include `cache_regression_runner.gd` and `cache_edge_regression_runner.gd`, covering changed dependencies, nested/shared preloads, repeated edits, first helper instantiation after rejected reloads, inheritance rollback, rejected-candidate cache cleanup, retained-resource cleanup and unused broken helpers. The reliability suite covers fallback snapshot preservation across reopening, startup failure rollback, changed dependencies (including preload), rename rebinding, immediate retry after Stop, cancelled compaction, atomic JSON replacement, and settings write failures. Node tests cover workspace roots, symlink/junction escapes, Git aliases, and exact versus unknown model capabilities. Pi acceptance also verifies a stalled provider connection is closed by Stop, immediate resume, and conversation preservation after rename.

`runtime_properties_runner.gd` exercises live inspection and batch property
mutation through GameTools and all fourteen controller bridges, including
identity/generation rejection, host boundaries, untyped fields, tagged 2D/3D
values, setter readback, invalidation, bounds and partial failures.
`runtime-properties.test.mjs` registers the tools from every canonically assembled
harness. Package contents acceptance also executes a live patch from the PCK.
See [the API contract](../../docs/runtime-properties.md).

`runtime_children_runner.gd` exercises mandatory isolated late-insertion smoke,
property initialization, parent identity/lifecycle, dependency cache freshness,
errors, cancellation, timeout, source/name races and the inherited OpenCode
bridge. Package contents acceptance executes addition and removal from the PCK.
See [the additive child API](../../docs/runtime-children.md).

`runtime_node_lifecycle_runner.gd` checks actual engine callbacks for initially
constructed and late-added subtrees: synchronous enter/ready ordering, unchanged
parent initialization and cached children, deferred work, process/physics ticks
and priority, reinsertion/request_ready, and inherited disabled processing.
It exercises Godot composition directly; structural runtime mutation tools are
not implied by this fixture. The measured integration caveats are included in
the shared generated-game prompt.

## Generated script loading policy

The reliability suite also checks chat-first opening without executing crash-prone code, idle-only manual Run/Reload controls, and agent-triggered startup from chat.

Run availability checks include empty workspaces, completion without creating `main.gd`, deletion after button enabling, and snapshot-only recovery. Execution status checks cover fallback/workspace transitions, failed reloads, and reopening without execution.

Agent reload approval regressions cover deferred bridge responses, continued gameplay and mouse ownership, Shift+F5 and chat-button approval, one approval per request, failed candidates and Stop cancellation. Real Pi acceptance verifies that generation/edit reloads wait for approval before the tool returns; other test turns explicitly approve through the same controller method.

Helper scripts must use `preload()` or script inheritance. Before touching the dependency cache, each load/reload checks all workspace `.gd` files (excluding `.git` and `.godot`) for direct runtime script loading calls and reports the offending file and line. A rejection keeps the accepted game and its preloaded dependencies intact. Comments and strings containing example code are ignored.

Identified direct runtime-loading calls are restricted to literal paths using approved ordinary asset formats: PNG/JPG/JPEG/WAV/OGG, case-insensitively. The same rule applies to `load()`, `ResourceLoader.load()`, `load_threaded_request()` and `load_threaded_get()`. Computed paths, UID paths, extensionless paths and every other format are rejected regardless of a non-script type hint. Explicit Script/GDScript hints are rejected even with an approved filename. Script dependencies should use `preload()` or script inheritance; scenes and serialized resources must use `preload()` with a statically known path.

The scanner recognizes bare `load()` and the three direct `ResourceLoader` methods above. Unrelated methods such as `ConfigFile.load()`, `Image.load()` and custom `.load()` methods are outside this policy, as are aliases and indirect calls. Comments and quoted examples are ignored. Unfinished strings, unmatched delimiters and invalid loading-call arity defer to Godot's compiler. This is a coding-policy check, not a security sandbox or complete revision isolation: indirect resource loading is prohibited by model instructions but outside the check, and games can still read ordinary files or assets later.

`script_load_policy_runner.gd` applies a shared safe/unsafe path matrix across all loading APIs, checks hints only on APIs that accept them, and tests malformed-call compiler rejection, file/line reporting, nested unused scripts, metadata exclusions, cache preservation, corrected reloads and model instructions. Both cache suites and the policy suite run in the usual portable and Linux verification commands.

## Real Pi acceptance

`run-pi-e2e.sh` starts `../fake-openai-endpoint/pi-server.mjs` and drives the actual globally installed `pi` executable over GameSmith's production JSONL RPC path. The deterministic server speaks streaming OpenAI-compatible `/v1/chat/completions` and requires only Node's standard library.

CI pins `@earendil-works/pi-coding-agent@1.4.0`. Pi 1.4.0 is the supported integration baseline; older releases are not supported. For local runs you may point GameSmith at another explicit Pi executable with `GAMESMITH_PI_BIN`.

The portable host runner imports the project with the headless editor before launching suites, using the same isolated application data. Diagnostic delivery tests verify that receipts remain pending until an exact tool result or hidden notice appears in the current Pi session branch, including errors, altered responses, branch changes and bounded receipt eviction.

The release gate runs the Pi suite once with no phase selector:

```bash
GODOT_BIN=/path/to/godot tools/testing/run-pi-e2e.sh
```

For focused development, `GAMESMITH_PI_TEST_PART=1`, `2`, `3`, or `4` still runs only that slice.

Part 1 covers production controller selection, missing-Pi diagnostics, generation/edit/reload/Git behavior, streaming assistant/thinking events, completion without forced edits or reloads, native retry behavior, action limits, provider-call pacing, Pi session restart/resume, hidden diagnostic notices, and filtered runtime-log reads through real Pi. Reload remains a model instruction; the host does not infer change intent or continue a settled turn to force missing tool work. Diagnostic delivery receipts are still confirmed at settlement.

`diagnostics_runner.gd` checks persistent startup/live capture, timestamps and attempt identities, unchanged startup rejection, session lifecycle, exact delivery receipts beyond 128 diagnostics, sparse grouped membership, filters, raw pagination, repeated reads, response trimming, cancellation before delivery, bounded acknowledgement state, queue overflow, retention, write failures, interrupted JSONL tails, recovery fast paths, Windows rename, and snapshot fallback. The reliability suite also exercises the production rename handler on success/failure and the formerly-used broken-helper cache regression. Both the portable host runner and full verification workflow include these suites.

`.github/workflows/verify-windows.yml` runs the host, reliability, diagnostics, Node, and real Pi acceptance tests natively on Windows using the bundled Godot runtime and pinned Pi. The existing Ubuntu packaging/verification job remains separate.

Part 2 covers manual and threshold-triggered Pi-native compaction, `keepRecentTokens`, persisted native compaction entries, checkpoint delivery to the next provider request, normal no-op classification, and byte-stable session entries across GameSmith restart.

Part 3 seeds a pre-Pi readable transcript and proves that it is imported into an empty Pi session exactly once, that the current request is not duplicated into the imported legacy block, that restart does not re-import it, and that production no longer contains the deleted homegrown agent/provider/compaction sources.

Part 4 verifies the explicit `GAMESMITH_PI_BIN` path, automatic discovery of a globally npm-installed `pi` from `PATH`, Windows README install guidance, and launcher-level Pi preflight behavior.

The production default Pi turn limit is 150. Runaway fixtures use a deliberately small test limit so acceptance does not waste provider round trips proving the same host-policy branch.

## Expected parse errors

Some host/runtime tests deliberately write invalid generated GDScript. Godot will print parse errors for those candidates. The tests only pass when GameSmith rejects the bad candidate, preserves or recovers the previous working game, and continues correctly.

## OpenCode acceptance

`opencode_lifecycle_runner.gd` is included in the default host suite and uses a fake
CLI with the real MCP adapter to verify approval, Stop, descendant cancellation,
session persistence, native errors and same-request reload repair. `harness_runner.gd`
checks OpenCode selection and preservation of disabled provider/compaction settings.

Run the installed CLI with your available provider using:

```powershell
node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe opencode_integration_runner.gd
```

This isolates host and OpenCode test data. It verifies native file edits, separate
headless tests, reopening the same native session, and a reload approval wait longer
than the MCP default deadline. It deliberately contacts the configured/default provider.
