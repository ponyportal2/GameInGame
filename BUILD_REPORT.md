# GameSmith verification report

## Current production architecture

GameSmith's production agent runtime is now Pi-native.

- GameSmith launches a globally installed `pi` process over JSONL RPC.
- Pi owns provider calls, model history, streaming assistant/thinking output, retries, generic coding tools, durable sessions, and native compaction.
- GameSmith owns the library/chat UI, generated-game workspace boundary, Git milestones, Godot reload/verification, last-working snapshot, readable transcript, logs, and product policy controls.
- The pinned verification target is `@earendil-works/pi-coding-agent@0.99.2`.
- No shell/bash/PowerShell tool is exposed to the model.

The previous homegrown `AgentController`, direct OpenAI-compatible provider/factory, `ConversationStore`, and `CompactionService` have been removed from the repository.

## Provider and Settings behavior

Provider metadata now lives under `src/pi/pi_provider_catalog.gd`. GameSmith maps OpenRouter, OpenCode Go, Command Code, Custom OpenAI-compatible, and OpenAI-subscription/global-auth choices into Pi configuration.

Settings exposes:

- global and per-game Pi provider/model selection;
- Custom `/v1` base URL;
- provider credential storage outside game workspaces;
- Pi reasoning/thinking level;
- Pi turn limit, default 150;
- provider-call delay, default 6 seconds;
- automatic Pi compaction threshold, default 100,000 current-context tokens;
- Pi `keepRecentTokens`, default 20,000;
- manual **Compact now**.

## Session persistence and migration

Existing Pi sessions are resumed directly; GameSmith does not reconstruct provider history from its readable transcript.

For a game that predates Pi and has readable user/assistant dialogue but no meaningful Pi history:

1. GameSmith starts/resumes Pi before writing the current request to `transcript.jsonl`.
2. Pi's `session_start` hook ignores bootstrap-only metadata entries and imports the pre-existing readable dialogue once as hidden `gamesmith-legacy-dialogue` context.
3. The current request is then appended to the readable transcript and sent normally.
4. On restart, the existing Pi session prevents a second import.

The Part 3 acceptance test proves that the legacy dialogue reaches the first provider request, the current request appears exactly once, the human-readable transcript remains unchanged except for the new turn, and Pi entries remain byte-stable across restart.

## Pi-native compaction and cache behavior

Manual and threshold-triggered compaction use Pi's native `compact` RPC. GameSmith writes the configured recent-token budget into Pi's own `compaction.keepRecentTokens` setting and reads Pi's canonical current-context usage to decide when to trigger the product-level threshold.

Between compactions, GameSmith leaves Pi history append-only. A compaction intentionally adds Pi's native checkpoint and changes the prompt prefix once; restarting GameSmith resumes the same Pi entries byte-for-byte before later work is appended. A normal "nothing to compact/session too small" result is surfaced as **Compaction skipped** rather than as a provider failure.

## Host/game behavior retained

- New/Open/Rename/Delete game library plus Folder, Logs, and Settings actions.
- Per-game Git repositories with baseline commits and agent-controlled milestones.
- 2D/3D GDScript runtime games loaded in the persistent Godot host.
- Failed generated candidates do not replace the last working game.
- Game-changing completion claims are verified at Pi settlement and can be rejected when workspace/reload evidence is missing.
- Chat owns input while open; hostile generated Controls/mouse capture cannot steal host interaction.
- Enter sends, Shift+Enter inserts a newline, Escape closes chat.
- Library navigation is blocked while Pi is busy.
- Global and per-game logs redact Authorization/API-key-like values.
- Writable app-data identity is `GameSmithHost`, with copy-forward migration from the old `GameSmith Host` directory.

## Verification

GitHub Actions run `36928625392` is the Part 3 green release check:

- fast host/core/UI suite: **125/125**;
- real windowed hostile-input suite: **20/20**;
- real globally installed Pi Part 1: **40/40**;
- Pi Part 2 native-compaction suite: **20/20**;
- Pi Part 3 migration/runtime-removal suite: **22/22**;
- process-level `GameSmith Host` → `GameSmithHost` migration: **pass**;
- complete source verification: **pass**;
- Windows folder build and refresh: **pass**.

The Windows refresh produced commit `7815186`.

The deliberate broken-candidate regression still emits GDScript parse errors in logs; those are expected evidence that invalid generated code is rejected while the previous working game survives.

## Remaining phased work

Part 4 of `.plan/pi-feature-parity-phased.md` remains intentionally unimplemented in this slice. It covers Windows-specific Pi installation/discovery guidance, explicit packaging behavior when Pi is missing, final global-install/`GAMESMITH_PI_BIN` checks, and the final release-gate presentation.
