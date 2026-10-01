# GameSmith verification report

## Current product behavior

- **Provider transport diagnostics:** OpenAI-compatible requests now use a 300s default timeout and distinguish Godot HTTP transport results (timeout/DNS/connect/TLS/no-response/etc.) from actual HTTP response codes.
- Provider request/response log entries include sanitized endpoint/model/context sizing, elapsed time, transport/HTTP result, response bytes, selected safe response headers and finish/token metadata when available.
- Completion verification is bounded to 3 consecutive no-op rejections; verifier prompts are ephemeral instead of permanently polluting provider history, and old persisted verifier pollution is filtered on replay.
- Interrupted prior turns are explicitly closed with a recovery marker before a later user request, avoiding ambiguous consecutive dangling user/tool history.

- Game library with New Game, Open, Rename, Delete, Folder, global Logs, and global Settings.
- Per-game Git repository with an immediate `Initialize game` baseline commit.
- GDScript-only runtime games mounted directly in the persistent host process; both 2D and 3D are supported.
- Runtime-loaded multi-file games, failed-candidate preservation, last-working snapshots, and explicit agent-controlled reloads.
- Durable readable transcript **and** full provider-visible conversation history (assistant tool calls/results included) replayed across app restarts with a cache-stable prefix.
- OpenRouter, OpenCode Go, Command Code, and Custom OpenAI-compatible `/v1` providers; optional Custom API key and configurable `reasoning_effort`.
- Completion guards reject text-only `Done` when required workspace work/reload has not actually happened.
- Host chat owns input while open, including against hostile generated full-screen Controls/mouse capture.
- Enter sends; Shift+Enter inserts a newline.
- Return to Library is disabled and guarded in code while the agent is busy.
- Agent action limit is persisted in Settings; default 150, allowed range 1–500.
- Writable app-data identity is `GameSmithHost` (no space), with safe copy-forward migration from the old `GameSmith Host` sibling directory.
- Bounded global `user://logs/gamesmith-app.log` plus bounded per-game `user://host/games/<game>/gamesmith.log`, with API-key/Authorization redaction.
- Compact library/chat action controls and Settings access from both library and game chat.

## Windows release ZIP

The repository root contains `GameSmith-Windows.zip` rather than a loose executable. After extraction it contains `GameSmith.exe`, `GameSmith.pck`, and the supplied Godot 4.7.2 Windows x64 runtime under `runtime/`.

Normal Windows startup is therefore fully local and does not download Godot. The launcher still retains its checksum-verified missing-runtime fallback, but the bundled executable satisfies the existing-runtime/no-network path.

Package verification checks ZIP integrity and requires the launcher, PCK, bundled runtime, and README to be present. The current release ZIP is below GitHub's 100 MB per-file Git limit.

`tools/windows-bootstrap/` contains the release launcher and unit tests for existing-runtime/no-network, missing-runtime download/cache, checksum rejection, invalid existing paths, and ZIP traversal rejection.

## Verification

Final source verification on Godot 4.7.2:

- self-contained root Windows ZIP verification: **pass**;
- Go Windows bootstrap tests: **pass**;
- fast Godot suite: **135/135**;
- real windowed hostile-input suite: **10/10**;
- real HTTP fake-`/v1/chat/completions` suite: **50/50**;
- two-process provider-visible conversation replay: **pass**;
- process-level old `GameSmith Host` → `GameSmithHost` migration: **pass**;
- fake-v1 acceptance workflow: **24 real HTTP requests** after keeping the runaway-limit HTTP fixture intentionally small (the separate fast/UI tests verify the production default of 150).

Coverage includes workspace traversal isolation, Git initialization/history, candidate compilation, sibling-script loading, preservation of a working game after broken candidates, generated-game frame processing, input ownership, Enter/Shift+Enter, busy navigation blocking, Settings persistence, default/custom action limits, app-data migration, global/per-game debug logs and secret redaction, simulated first generation + second edit, false-completion recovery, required post-edit reload, provider failures, malformed tool arguments, cache-stable conversation replay, custom `/v1` address normalization, exact `reasoning_effort` payload behavior, real UI keyboard-to-HTTP-provider flow, HTTP 500/invalid JSON, failed-reload repair, and restart persistence.

The deliberate broken-candidate tests emit GDScript parse errors into test output; those errors are expected evidence that the previous game survives bad generated code.

## Deliberate v1 limitations

- No screenshot/vision tool or autonomous gameplay input.
- No state-preserving reload.
- No separate-process sandbox for generated GDScript.
- No binary asset pipeline.
- No automatic provider call merely because a runtime error occurred.
- OpenAI ChatGPT subscription login is not scraped/faked; it remains behind the provider seam until an appropriate embeddable authentication path is used.
