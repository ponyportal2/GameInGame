# Pi feature-parity migration — phased plan

Goal: replace GameSmith's homegrown agent runtime with a globally installed Pi process without trying to land the entire migration in one execution window.

Pinned integration target for tests: `@earendil-works/pi-coding-agent@0.99.2`.

## Rules for the migration

- Production GameSmith talks to a global `pi` executable over JSONL RPC.
- Pi owns generic agent behavior: provider calls, model history, reasoning, streaming, retries, coding tools, session persistence, and compaction.
- GameSmith owns game-specific behavior: library/UI, workspace isolation, Git milestones, Godot reload/verification, last-working snapshot, logs, input ownership, and host policy controls.
- Preserve prompt-cache friendliness: do not rewrite Pi history between normal turns; restarting GameSmith must resume the existing Pi session rather than reconstructing it.
- No shell tool is exposed to the model.
- TDD remains red -> green. Each phase gets its own acceptance gate; later known-red phases are not treated as failures of the completed phase.
- Do not delete the old agent/provider implementation until the Pi replacement has equivalent acceptance coverage.

## Part 1 — normal Pi agent runtime — COMPLETE

Scope:

- production App uses `PiAgentController`;
- discover a globally installed `pi` and fail clearly when missing;
- long-lived JSONL RPC subprocess;
- custom OpenAI-compatible provider/base URL/API key mapping;
- reasoning level mapping;
- true assistant/thinking event delivery;
- Pi built-in read/edit/write/grep/find/ls, with no bash/PowerShell;
- GameSmith extension tools: delete/move/Git/reload/runtime log;
- generation -> reload -> Git milestone;
- second conversation edit -> reload;
- false-`Done` verifier continuation;
- provider retry behavior;
- configurable action limit;
- configurable delay between provider calls;
- Pi session restart/resume with stable existing history;
- UI keeps Enter/Shift+Enter, busy navigation blocking, and transcript behavior.

Acceptance boundary: all Pi integration tests **except compaction** plus the existing core/windowed suites.

Status at plan creation: current real-Pi suite was **42 passed / 5 failed**, and all five failures were compaction-only. Core was **228/228** and windowed was **20/20**.

Part 1 completion:

- Added an explicit phase selector to the real-Pi integration runner; `GAMESMITH_PI_TEST_PART=1` runs only the normal-agent slice, while the default still runs the complete suite.
- Added a missing-global-Pi acceptance check with a clear pre-launch error.
- CI's phased release gate now runs Part 1 only. This does **not** mark compaction as passing; Part 2 remains separately runnable and intentionally unfinished.
- Production remains Pi-backed; no rollback to the homegrown provider loop was used to make this phase green.
- Verified on GitHub Actions run `36923886630`:
  - core: **228 passed / 0 failed**;
  - windowed UI/input: **20 passed / 0 failed**;
  - real globally-installed Pi Part 1: **40 passed / 0 failed**;
  - legacy app-data migration: pass;
  - source verification: pass;
  - Windows folder build/refresh: pass.
- Part 1 acceptance commits: `e1800b5` (phase split), `dadf301` (runner selector), `2d1d6db` (CI Part 1 gate), followed by Windows refresh `1b7e3e3`.
- Cache behavior covered in Part 1: normal Pi history survives process restart without GameSmith rebuilding/reducing it; the existing pre-turn session prefix remains stable until Pi itself appends new entries.

Known remaining red work is deliberately confined to **Part 2 compaction**.

## Part 2 — Pi-native compaction parity — COMPLETE

Scope:

- manual Compact now calls Pi native compaction;
- automatic threshold triggers Pi compaction;
- configured keep-recent token policy maps correctly;
- compaction summary is persisted by Pi;
- next provider call receives compacted context;
- manual UI shows progress/success/failure and blocks sends;
- verify cache-friendly session behavior across compaction and restart.

Acceptance boundary: compaction-specific real-Pi tests only.

Part 2 completion:

- Manual **Compact now** calls Pi's native `compact` RPC; GameSmith no longer generates its own production checkpoint for the Pi path.
- The configured `compaction_keep_recent_tokens` value is written into Pi's own `compaction.keepRecentTokens` setting and is asserted in the real-Pi acceptance test.
- GameSmith keeps Pi's built-in threshold auto-compaction disabled and applies the product's explicit configurable token threshold by reading Pi's canonical `get_session_stats.contextUsage.tokens`; crossing the threshold invokes Pi's native `compact`.
- Tests require a real Pi `type: "compaction"` session entry, not a string/shape approximation.
- The next normal provider request must contain Pi's compacted checkpoint context.
- A native compacted session is restarted in a new GameSmith controller and its Pi entry prefix must remain byte-stable before the next prompt; the provider then receives the checkpoint after restart.
- Manual UI progress/success/failure and send/navigation blocking remain covered by the existing core UI tests.
- Pi's explicit `Nothing to compact (session too small)` result is surfaced as **Compaction skipped**, not a provider/summary failure.
- TDD evidence:
  - initial native-Pi Part 2 gate: **8 passed / 5 failed**;
  - corrected compactable-span fixture: **11 passed / 2 failed**;
  - native compaction/restart/context acceptance: **19 passed / 0 failed**;
  - no-op RED commit `dd690db`: **19 passed / 1 failed**;
  - no-op GREEN commit `cc5fbb2`: **20 passed / 0 failed**.
- Final verification run `36926099737`:
  - core: **228/228**;
  - windowed: **20/20**;
  - real global-Pi Part 1: **40/40**;
  - real global-Pi Part 2: **20/20**;
  - legacy app-data migration: pass;
  - source verification: pass;
  - Windows folder refresh: `f9b67cf`.
- Cache behavior: GameSmith never reconstructs or continuously compacts Pi history. Native Pi owns the append-only session and checkpoint entry; after compaction, restart preserves those entries byte-for-byte until Pi appends new work.


## Part 3 — migration and deletion of duplicate agent code — COMPLETE

Scope:

- one-time legacy readable transcript import into an empty Pi session;
- preserve existing per-game readable transcript/log UX;
- remove production dependencies on the homegrown provider loop;
- delete obsolete ConversationStore/CompactionService/provider-loop code only after replacement tests are green;
- simplify Settings/provider wording around Pi;
- update docs and third-party notices.

Acceptance boundary: migration/restart tests plus source-level checks that production no longer references the deleted runtime.

Part 3 completion:

- Added a dedicated `GAMESMITH_PI_TEST_PART=3` gate covering migration, restart stability, readable-transcript ownership, and source-level legacy-runtime removal.
- Fixed first-turn ordering so GameSmith starts/resumes Pi before appending the current user request to the readable transcript. A current request therefore cannot be accidentally imported as pre-Pi history and then sent again.
- Corrected the definition of an "empty" Pi session for migration: Pi bootstrap entries such as `model_change`, `thinking_level_change`, and `session_info` do not count as conversational history. Existing message/custom/compaction history still prevents re-import.
- Pre-Pi readable user/assistant dialogue is injected into a genuinely empty Pi session once as hidden `gamesmith-legacy-dialogue` context. Restarting the same Pi session does not import it again.
- The human-readable `transcript.jsonl` remains a GameSmith UI/log artifact containing user and final assistant turns; it is no longer the provider-history store.
- Added `src/pi/pi_provider_catalog.gd` and moved provider display/default/base/auth mapping out of the deleted provider factory.
- Deleted the obsolete homegrown `AgentController`, `ConversationStore`, `CompactionService`, direct OpenAI-compatible provider/factory, their runtime-specific tests, and the superseded fake-v1 acceptance server.
- Removed the dead `conversation.jsonl` metadata accessor.
- Settings now consistently describes Pi provider/model/turn/pacing/compaction behavior.
- README, verification docs, fake-endpoint notes, and third-party notices now describe the Pi-native runtime rather than the deleted direct-provider loop.
- RED gate: commit `970a4f6`. The first migrated-code CI run exposed the Pi-bootstrap-metadata edge case with Part 3 at **20 passed / 2 failed**.
- GREEN fix: commit `8f52665`.
- Verified on GitHub Actions run `36928625392`:
  - fast host/core/UI: **125 passed / 0 failed**;
  - windowed UI/input: **20 passed / 0 failed**;
  - real globally-installed Pi Part 1: **40 passed / 0 failed**;
  - Pi Part 2 compaction: **20 passed / 0 failed**;
  - Pi Part 3 migration/deletion: **22 passed / 0 failed**;
  - legacy app-data migration: pass;
  - source verification: pass;
  - Windows folder build/refresh: pass.
- Windows refresh commit: `7815186`.

## Part 4 — packaging and release gate — COMPLETE

Scope:

- Windows behavior when Pi is globally installed;
- clear startup/install guidance when Pi is missing;
- verify npm/global-install path and explicit `GAMESMITH_PI_BIN` override;
- final Windows folder build;
- restore one full verification command that runs core + windowed + all Pi phases;
- final README/BUILD_REPORT cleanup.

Acceptance boundary: complete CI green with no allowed/red migration tests.

Part 4 completion:

- Added launcher-level Pi preflight on Windows. Missing Pi is a non-blocking warning: GameSmith still opens so the library/settings remain usable, but the warning gives the pinned install command and explains that chat build/edit needs Pi.
- The pinned Windows guidance is `npm install -g @earendil-works/pi-coding-agent@0.99.2`; `GAMESMITH_PI_BIN` remains the explicit escape hatch for a Pi executable outside `PATH`.
- Added Go tests for explicit override resolution, a Windows-style global npm `pi.cmd` lookup, and actionable missing-Pi guidance.
- Added real-Pi Part 4 acceptance that verifies both the explicit `GAMESMITH_PI_BIN` path and automatic globally installed `pi` discovery from `PATH`.
- The committed/generated Windows README now includes the pinned Pi install command and override guidance.
- Restored the release gate to one Pi invocation with no phase selector; the single process runs Parts 1–4 together, avoiding repeated setup while preserving the same real-Pi session/restart checks.
- No Part 4 runtime change rewrites Pi history, session IDs, or compaction state. Cache-friendly append-only/resume behavior from Parts 1–3 remains unchanged.
- Added workflow concurrency so stale Windows-package builds are cancelled instead of racing to push generated binaries.
- TDD RED: commits `e6da241`, `542766b`, and `a8b05f8`; GitHub Actions run `37022883507` failed at the launcher unit-test step with `undefined: resolvePiExecutable`.
- GREEN implementation: launcher preflight `48978b2`, runtime guidance `10f1c2c`, Windows package guidance `f66ca98`, and CI single-flight fix `4c172d4`.
- Final green GitHub Actions run `37023404746`:
  - Windows package structural verification: pass;
  - fast host/core/UI: **125 passed / 0 failed**;
  - windowed UI/input: **20 passed / 0 failed**;
  - real Pi all-phases acceptance: **83 passed / 0 failed**;
  - legacy app-data migration: pass;
  - complete source verification: pass;
  - Windows folder build/refresh and push: pass.
- Final Windows refresh commit for the implementation slice: `c1d1280`.

## Stop rule

All four migration parts are complete. Further work should be treated as normal product work, not as unfinished Pi feature-parity migration. Keep the established ownership boundary: Pi owns generic agent/session behavior; GameSmith owns game-specific host behavior.
