# TODO — replace GameSmith agent runtime with Pi

Target: production GameSmith talks to a globally installed `pi` process in RPC mode. Pi owns provider calls, sessions, reasoning, streaming, retries, tools, and compaction. GameSmith keeps only game-specific host behavior.

Pinned test/runtime reference: Pi 0.99.2 (the user-supplied Linux x64 binary and matching npm package).

## Boundary

Pi owns:
- provider/model protocol
- durable session history
- prompt-cache-friendly transcript semantics
- thinking/reasoning blocks
- true message streaming
- retries
- read/edit/write/grep/find/ls
- compaction and compaction summaries

GameSmith owns:
- game library/UI
- workspace root and Git repository
- generated-game runner
- reload/compile verification
- last-working snapshot
- per-game/global logs
- navigation/input ownership
- provider settings UI mapped into Pi config
- configurable host policy: action limit, inter-call delay, explicit auto-compaction token threshold

## TDD / migration

- [ ] RED: Pi binary discovery and long-lived JSONL RPC over Godot `OS.execute_with_pipe`.
- [ ] RED: real supplied/global Pi against fake OpenAI-compatible streaming endpoint.
- [ ] RED: Pi events surface true AGENT / THINK / TOOL activity.
- [ ] RED: Pi session survives GameSmith/Pi process restart.
- [ ] RED: custom OpenAI-compatible base URL + API key + reasoning level mapping.
- [ ] RED: built-in Pi read/edit/write operate inside game workspace; no bash exposed.
- [ ] RED: GameSmith extension provides delete/move/git/reload/runtime-log tools.
- [ ] RED: reload tool round-trips Pi extension -> host bridge -> GameRunner -> Pi result.
- [ ] RED: false "Done" completion is continued through Pi's `agent_before_settle` boundary without fake user messages.
- [ ] RED: 150-turn default host action limit aborts runaway Pi sessions.
- [ ] RED: 6-second default provider-call delay is enforced inside Pi between tool turns.
- [ ] RED: manual compaction invokes Pi RPC `compact`; auto threshold uses Pi session stats then Pi `compact`.
- [ ] RED: restart keeps cache-friendly Pi session prefix; no GameSmith conversation reducer.
- [ ] GREEN: switch production App to Pi controller.
- [ ] GREEN: preserve existing UI transcript; migrate readable legacy GameSmith transcript into a new Pi session once.
- [ ] GREEN: Settings changes restart only the Pi runtime, not the game.
- [ ] GREEN: clear user-facing error when global `pi` is missing.
- [ ] REMOVE: homegrown OpenAI provider loop, ConversationStore compaction semantics, and custom CompactionService once Pi-backed acceptance is green.
- [ ] VERIFY: core + windowed + real Pi/fake-v1 + restart + Windows folder.
