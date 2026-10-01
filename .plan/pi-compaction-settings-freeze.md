# TODO — Pi-style compaction + Settings freeze

## Research target

Mirror Pi coding-agent compaction semantics, adapted only where GameSmith's simpler linear OpenAI-message session requires it:

- Raw conversation remains append-only.
- No continuous per-turn compaction.
- Automatic compaction happens only when configured token threshold is crossed.
- Manual compaction is always available.
- Walk backward from newest messages and retain approximately `keepRecentTokens`.
- Never cut at a tool-result message; preserve tool-call/result validity.
- If the cut is in the middle of a turn, summarize the old history and the turn prefix separately, then merge them exactly in Pi's checkpoint shape.
- Generate structured checkpoint with Pi's exact Goal / Constraints / Progress / Key Decisions / Next Steps / Critical Context prompt.
- On later compactions, feed the previous checkpoint into Pi's update prompt instead of re-summarizing from scratch.
- Serialize conversation as text for the summarizer; truncate serialized tool results to 2000 characters only for that one summarization request.
- Track read/modified files and append Pi-style `<read-files>` / `<modified-files>` sections.
- Provider-facing compaction summary uses Pi's exact "conversation history before this point..." wrapper.
- Keep compaction cache-friendly: checkpoint changes only when compaction occurs; retained tail remains byte-identical.

## Product controls

- [x] Settings: auto-compaction threshold in estimated tokens; default 100000; 0 disables.
- [x] Settings: recent-token keep budget; default 20000.
- [x] Settings: manual **Compact now** button for the current game.
- [x] Show compacting state/result without inserting fake chat history.
- [x] Prevent manual compaction while agent is already busy.

## Settings freeze

- [x] RED: Settings must not be a modal `Window` outside the reserved host CanvasLayer.
- [x] GREEN: replace general Settings with a host-owned in-canvas overlay.
- [x] Windowed regression: open Settings while game/chat is paused, interact with it, close it, and confirm chat/game state remains correct.

## TDD

- [x] RED: defaults + controls + in-canvas Settings assertions.
- [x] RED: Pi-style append-only checkpoint/cut/replay contract.
- [x] GREEN: compaction store and summarizer.
- [x] GREEN: auto-trigger and manual action.
- [x] GREEN: settings overlay freeze fix.
- [x] HTTP regression: summarization call has no tools and resulting checkpoint is used by the next normal request.
- [x] Full source/windowed/fake-v1/restart/Windows-folder verification.


## Outcome

- RED contract commit: `87fee7f`.
- Pi-style append-only compaction core: `77f2e1a`.
- Compaction settings + tool-free summary payloads: `b9de9da`.
- Agent auto/manual compaction lifecycle: `ff07753`.
- In-canvas Settings overlay + compaction controls: `211c57b`.
- Compaction/store/windowed tests: `c7acaa4`.
- Automatic threshold regression: `c154d2e`.
- Real OpenAI-compatible HTTP compaction acceptance: `169a3d5`.
- Final green CI: **212/212 core**, **20/20 windowed**, **67/67 real fake-v1 HTTP**, restart/migration verification and self-contained Windows folder all pass.
- CI release refresh: `e8246b0`.
- Cache policy: raw history is append-only; no per-turn history rewrite. Prefix changes only at an explicit checkpoint, then checkpoint + retained tail remain stable until the next checkpoint.
- Intentional GameSmith adaptation from Pi: automatic trigger uses a user-configured estimated-token threshold because arbitrary custom providers do not supply reliable context-window metadata. The compaction/cut/summarization behavior itself follows Pi's linearizable core.
