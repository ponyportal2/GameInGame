# GameSmith verification report

## Final Pi feature-parity state

The four-part Pi migration is complete.

- Production GameSmith launches a globally installed `pi` process over JSONL RPC.
- Pi owns provider calls, model history, streaming assistant/thinking output, retries, generic coding tools, durable sessions, and native compaction.
- GameSmith owns the library/chat UI, generated-game workspace boundary, Git milestones, Godot reload/verification, last-working snapshot, readable transcript, logs, input ownership, and product policy controls.
- The pinned verification target is `@earendil-works/pi-coding-agent@0.99.2`.
- The previous homegrown `AgentController`, direct provider/factory, `ConversationStore`, and `CompactionService` are gone.
- No shell/bash/PowerShell tool is exposed to the model.

## Windows and Pi discovery

The root `GameSmith-Windows/` folder remains self-contained for the Godot runtime. Pi itself is intentionally global rather than bundled.

The Windows launcher now preflights Pi before starting Godot:

- a globally installed npm Pi on `PATH` is accepted;
- an explicit `GAMESMITH_PI_BIN` executable is accepted;
- missing Pi shows a non-blocking warning with the exact pinned install command:
  `npm install -g @earendil-works/pi-coding-agent@0.99.2`;
- GameSmith still opens when Pi is missing so non-agent host UI remains usable.

The committed/generated Windows README contains the same guidance.

## Session persistence, compaction, and cache behavior

Existing Pi sessions are resumed directly. GameSmith does not rebuild provider history from the readable transcript.

Pre-Pi readable dialogue is imported only when a session has no meaningful conversational history. Pi bootstrap metadata does not suppress that one-time import, and the current player request is appended only after Pi starts, so it cannot be duplicated into legacy context.

Manual and threshold-triggered compaction use Pi's native `compact` RPC. GameSmith passes `compaction.keepRecentTokens` and uses Pi's current-context usage only to decide when the product-level threshold fires.

Between compactions, GameSmith leaves Pi history append-only. Restart tests require the persisted Pi entry prefix to remain byte-stable before new work. Part 4 made no changes to session IDs, history rewriting, or compaction semantics.

## Host/game behavior retained

- New/Open/Rename/Delete game library plus Folder, Logs, and Settings actions.
- Per-game Git repositories and agent-controlled milestones.
- 2D/3D GDScript runtime games loaded in the persistent Godot host.
- Failed generated candidates do not replace the last working game.
- Completion claims are verified at Pi settlement against workspace/reload state.
- Chat owns input while open, including against hostile generated Controls/mouse capture.
- Enter sends, Shift+Enter inserts a newline, Escape closes chat.
- Library navigation is blocked while Pi is busy.
- Global/per-game logs redact Authorization/API-key-like values.
- Writable app-data identity is `GameSmithHost`, with copy-forward migration from `GameSmith Host`.

## Final verification

Part 4 used a real TDD RED → GREEN cycle.

RED run `37022883507` failed in the Windows launcher tests because the newly required `resolvePiExecutable` behavior did not exist yet.

GREEN run `37023404746` completed the full release workflow:

- self-contained Windows package verification: **pass**;
- Go launcher/unit tests: **pass**;
- fast host/core/UI suite: **125/125**;
- real windowed hostile-input suite: **20/20**;
- one real-Pi all-phases suite: **83/83**;
- explicit `GAMESMITH_PI_BIN` discovery: **pass**;
- automatic globally installed Pi/`PATH` discovery: **pass**;
- process-level `GameSmith Host` → `GameSmithHost` migration: **pass**;
- complete source verification: **pass**;
- Windows folder build/refresh/push: **pass**.

Implementation-slice Windows refresh commit: `c1d1280`.

The deliberate broken-candidate regression still emits a GDScript parse error in test logs; that is expected evidence that invalid generated code is rejected while the previous working game survives.
