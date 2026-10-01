# TODO — manual compaction chat feedback

User-visible issue: Compact now runs behind Settings with no durable on-screen indication in chat, and the composer still looks sendable even though AgentController.busy rejects sends.

- [x] RED: manual compaction must immediately show a HOST progress line in chat.
- [x] RED: Settings should return to chat when manual compaction begins so progress is visible.
- [x] RED: disable composer, Send, and Library while manual compaction owns the agent.
- [x] RED: attempted sends during compaction must not enter conversation history.
- [x] RED: explicit success message in chat.
- [x] RED: explicit provider/summary failure message in chat.
- [x] RED: progress/result lines stay ephemeral and do not pollute transcript.jsonl.
- [x] GREEN: centralize chat busy-control state instead of special-casing compaction.
- [x] GREEN: restore controls on both success and failure.
- [x] VERIFY: core + windowed + real fake-v1 + Windows folder.


## Outcome

- RED commit: `cd2f53e`; expected UI failures proved the previous manual-compaction UX had no visible chat progress and left controls looking sendable.
- GREEN implementation: `cee3112`.
- Manual **Compact now** now closes Settings back to chat, immediately posts an ephemeral HOST "Compacting conversation…" line, disables the composer/Send/Library for the whole operation, and posts an explicit finished/skipped/failed result.
- Attempted sends while compaction owns the agent remain blocked and do not enter provider history.
- Status lines are UI-only; they do not pollute `transcript.jsonl` or future model context.
- Final verification: **228/228 core**, **20/20 windowed**, **67/67 real fake-v1 HTTP**; source verification and self-contained Windows folder passed.
- CI release refresh: `c3dd9fb`.
