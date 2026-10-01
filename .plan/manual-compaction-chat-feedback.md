# TODO — manual compaction chat feedback

User-visible issue: Compact now runs behind Settings with no durable on-screen indication in chat, and the composer still looks sendable even though AgentController.busy rejects sends.

- [x] RED: manual compaction must immediately show a HOST progress line in chat.
- [x] RED: Settings should return to chat when manual compaction begins so progress is visible.
- [x] RED: disable composer, Send, and Library while manual compaction owns the agent.
- [x] RED: attempted sends during compaction must not enter conversation history.
- [x] RED: explicit success message in chat.
- [x] RED: explicit provider/summary failure message in chat.
- [x] RED: progress/result lines stay ephemeral and do not pollute transcript.jsonl.
- [ ] GREEN: centralize chat busy-control state instead of special-casing compaction.
- [ ] GREEN: restore controls on both success and failure.
- [ ] VERIFY: core + windowed + real fake-v1 + Windows folder.
