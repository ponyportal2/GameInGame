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

## Part 1 — normal Pi agent runtime

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

Status at plan creation: current real-Pi suite is **42 passed / 5 failed**, and all five failures are compaction-only. Core is **228/228** and windowed is **20/20**.

## Part 2 — Pi-native compaction parity

Scope:

- manual Compact now calls Pi native compaction;
- automatic threshold triggers Pi compaction;
- configured keep-recent token policy maps correctly;
- compaction summary is persisted by Pi;
- next provider call receives compacted context;
- manual UI shows progress/success/failure and blocks sends;
- verify cache-friendly session behavior across compaction and restart.

Acceptance boundary: compaction-specific real-Pi tests only.

## Part 3 — migration and deletion of duplicate agent code

Scope:

- one-time legacy readable transcript import into an empty Pi session;
- preserve existing per-game readable transcript/log UX;
- remove production dependencies on the homegrown provider loop;
- delete obsolete ConversationStore/CompactionService/provider-loop code only after replacement tests are green;
- simplify Settings/provider wording around Pi;
- update docs and third-party notices.

Acceptance boundary: migration/restart tests plus source-level checks that production no longer references the deleted runtime.

## Part 4 — packaging and release gate

Scope:

- Windows behavior when Pi is globally installed;
- clear startup/install guidance when Pi is missing;
- verify npm/global-install path and explicit `GAMESMITH_PI_BIN` override;
- final Windows folder build;
- restore one full verification command that runs core + windowed + all Pi phases;
- final README/BUILD_REPORT cleanup.

Acceptance boundary: complete CI green with no allowed/red migration tests.

## Stop rule

For this execution, finish **Part 1 only**. Do not implement or paper over Part 2 compaction failures, and do not delete the old agent stack yet.
