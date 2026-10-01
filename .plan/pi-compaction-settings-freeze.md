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

- [ ] Settings: auto-compaction threshold in estimated tokens; default 100000; 0 disables.
- [ ] Settings: recent-token keep budget; default 20000.
- [ ] Settings: manual **Compact now** button for the current game.
- [ ] Show compacting state/result without inserting fake chat history.
- [ ] Prevent manual compaction while agent is already busy.

## Settings freeze

- [x] RED: Settings must not be a modal `Window` outside the reserved host CanvasLayer.
- [ ] GREEN: replace general Settings with a host-owned in-canvas overlay.
- [ ] Windowed regression: open Settings while game/chat is paused, interact with it, close it, and confirm chat/game state remains correct.

## TDD

- [x] RED: defaults + controls + in-canvas Settings assertions.
- [x] RED: Pi-style append-only checkpoint/cut/replay contract.
- [ ] GREEN: compaction store and summarizer.
- [ ] GREEN: auto-trigger and manual action.
- [ ] GREEN: settings overlay freeze fix.
- [ ] HTTP regression: summarization call has no tools and resulting checkpoint is used by the next normal request.
- [ ] Full source/windowed/fake-v1/restart/Windows-folder verification.
