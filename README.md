# GameSmith

GameSmith is a Godot 4.7 host for creating and iterating on small games by chatting with a coding agent. Every generated game lives in its own Git workspace. Production agent behavior is provided by a globally installed **Pi coding agent** process; GameSmith owns the game library/UI, workspace boundary, Git milestones, Godot reload/verification, readable transcript, logs, and host policy controls.

The integration/test target is `@earendil-works/pi-coding-agent@1.0.0`.

## Windows

The repository root contains a self-contained **`GameSmith-Windows/`** folder:

```text
GameSmith-Windows/
  GameSmith.exe
  GameSmith.pck
  README.txt
  THIRD_PARTY_NOTICES.md
  runtime/
    Godot_v4.7.2-stable_win64.exe
```

Clone/download the repository, open `GameSmith-Windows`, and double-click **`GameSmith.exe`**. The bundled Godot runtime means normal startup needs no Godot download. Git for Windows must be installed and available on `PATH` for generated-game repositories.

GameSmith also expects a global `pi` executable. Install the pinned build with:

```bash
npm install -g @earendil-works/pi-coding-agent@1.0.0
```

On Windows, `GameSmith.exe` checks for Pi at startup. If Pi is missing, it shows a non-blocking warning with this install command and still opens GameSmith; chat build/edit becomes available after Pi is installed and GameSmith is restarted. If Pi is installed outside `PATH`, set `GAMESMITH_PI_BIN` to the executable path (for npm on Windows, typically a `pi.cmd` shim).

For development on Linux:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path .
```

The Windows launcher source and unit tests are under `tools/windows-bootstrap/`.

## Settings

Use **Settings** from either the library or an open game's chat toolbar. Current controls are Pi-oriented:

- global Pi provider and model;
- optional Custom OpenAI-compatible `/v1` base address;
- provider API key passed to Pi;
- Pi thinking/reasoning level;
- **Pi turn limit per request**, default **150**, configurable from 1 to 500;
- **Delay between Pi provider calls**, default **6 seconds**;
- **Automatic Pi compaction threshold**, default **100,000 current-context tokens**; set to **0** to disable GameSmith's threshold;
- **Recent tokens kept verbatim by Pi compaction**, default **20,000**;
- **Compact now** when a game is open.

OpenRouter, OpenCode Go, Command Code, and Custom OpenAI-compatible routes are mapped into Pi configuration. Custom can be used without an API key for local servers. **OpenAI subscription** delegates to Pi's global `openai-codex` authentication instead of GameSmith implementing a separate subscription token flow.

Per-game provider/model overrides remain available. Saving provider/model/thinking settings restarts only that game's Pi runtime; the generated game itself is not restarted.

Model capabilities come from Pi's installed catalog for exact provider/model matches. Unknown models, including arbitrary Custom endpoints, use conservative budgets of **8,192 context tokens** and **1,024 output tokens**, with reasoning disabled. These budgets are not claims about the server's actual limits. Compaction settings never change model capabilities; automatic compaction and retained context are capped to the available budgets.

Important JSON files are replaced through a flushed temporary file. Settings reports any failed writes and stays open so you can retry; a partial save is reported explicitly.

## Agent activity and tools

Pi streams assistant text and provider-exposed thinking to GameSmith while a turn is running. GameSmith also shows short ephemeral **TOOL** activity snippets. Intermediate activity is not written to the human-readable transcript.

The model receives Pi's built-in coding tools such as `read`, `edit`, `write`, `grep`, `find`, and `ls`. GameSmith's Pi extension adds game-specific tools:

- `delete_path`, `move_path`;
- `git_status`, `git_diff`, `git_log`, `git_commit`;
- `reload_game`;
- `read_runtime_log`.

No shell/bash/PowerShell tool is exposed to the model.

Pi decides when its turn is complete. GameSmith instructs it to call `reload_game` after editing the game. Provider retries, model history, reasoning, coding-tool execution, session persistence, and generic compaction semantics remain Pi-owned.

Games always open in chat without executing generated code, so after a game crashes GameSmith you can reopen its chat and ask Pi to repair it. **Run Game** starts execution; **Reload Game** is available in chat and gameplay once a game is running. Both manual controls are disabled while the agent is working. Pi's `reload_game` waits indefinitely for approval: a notice over the game leaves gameplay input and mouse untouched; press **Shift+F5**, or **F1** and click **Allow Reload** in chat. **Stop** cancels the waiting agent. Generated games still share the host process: running broken code can crash GameSmith again.

Run is available only when workspace `main.gd` or a last working snapshot exists. Chat and gameplay show persistent execution status: **Not running**, **Running workspace**, or **Running last working snapshot**. This identifies the loaded source, without claiming it includes later file edits.

## Library/chat behavior

- **F1** toggles chat.
- **Enter** sends.
- **Shift+Enter** inserts a newline.
- **Escape** closes chat.
- **Return to Library** is disabled and programmatically blocked while Pi is working.
- **Stop** cancels a request or manual compaction, shuts down the Pi process, and restores chat/navigation controls. Workspace edits already made are kept; the next request resumes the saved Pi session.
- Rename is blocked while Pi is working. Renaming an open game retires Pi before moving its directories, rebinds its persisted session header to the new workspace, and preserves conversation entries.
- While chat is open, GameSmith owns input: generated processing and generated `Control` mouse interception are suspended, captured mouse mode is released, and the prior gameplay input state is restored when chat closes.

Settings is rendered as a host-owned in-canvas overlay above generated-game CanvasLayers.

Reload rejects compile errors and synchronous startup errors while keeping the previous game. Cached GDScript dependencies are replaced with current source for the candidate and restored if it fails. Loading the last working snapshot never promotes the broken workspace over that snapshot.

## Data, sessions, and logs

The writable application directory is named **`GameSmithHost`**.

On Windows this is normally:

```text
%APPDATA%\Godot\app_userdata\GameSmithHost\
```

On first launch after upgrading from v1.4 or earlier, GameSmith copies missing files from the old sibling `GameSmith Host` directory into `GameSmithHost`. Existing files in the new directory win, and the old directory is left untouched as a safety copy.

Important paths:

- `user://games/<game>/` — generated game workspace and Git repository;
- `user://host/games/<game>/transcript.jsonl` — readable user/final-assistant transcript used by the UI;
- `user://host/games/<game>/pi/` — GameSmith's Pi agent config, bridge files, and native Pi sessions;
- `user://host/games/<game>/gamesmith.log` — per-game host/Pi/tool/reload log;
- `user://host/credentials.json` — provider credentials outside game workspaces;
- `user://logs/gamesmith-app.log` — global GameSmith log.

Logs are bounded and redact Authorization/API-key-like values.

### Legacy transcript migration

A game that has readable pre-Pi dialogue but no Pi session imports that dialogue into the **empty Pi session once**. GameSmith starts/resumes Pi before appending the current player request to `transcript.jsonl`, so that new request cannot be mistaken for legacy history. Once the Pi session has entries, restart/resume does not import the readable transcript again.

The readable transcript remains a product/UI artifact. It is not used to reconstruct an existing Pi provider history.

## Pi-native compaction and prompt-cache friendliness

Pi owns the durable agent session, including assistant reasoning, tool calls/results, checkpoint entries, and compaction.

GameSmith keeps only product-level controls around Pi's native compactor:

- **Auto compact at estimated tokens** defaults to 100,000; 0 disables GameSmith's trigger.
- **Keep recent tokens verbatim** defaults to 20,000 and is written to Pi's `compaction.keepRecentTokens`.
- **Compact now** invokes Pi's native `compact` RPC.
- GameSmith disables Pi's separate automatic threshold so there is one user-visible automatic policy.
- If Pi reports that a session is too small to compact, GameSmith shows **Compaction skipped** rather than treating it as a provider failure.

Between compactions, GameSmith does not rebuild or rewrite Pi history. A native compaction intentionally changes the prefix once by adding Pi's checkpoint; the checkpoint plus retained recent tail then remain stable until further work is appended. Restarting GameSmith resumes the same Pi session. Real-Pi acceptance tests compare persisted entries byte-for-byte across restart and verify that the next provider request receives Pi's checkpoint.

Actual provider-side prompt-cache eligibility, prefix-size requirements, TTLs, and billing remain provider/model-specific.

## Failures and diagnostics

GameSmith logs Pi process lifecycle, retries, tool execution, compaction, stderr, reload state, and host verification. A missing configured/global Pi executable fails before process launch with a clear user-facing error.

The Pi process owns provider transport and retry behavior. For debugging a game turn, the useful artifacts are the per-game `gamesmith.log`, its Pi session directory, and the generated workspace/Git history. The readable transcript is useful for the player-visible conversation but is not the full provider trace.

Runtime diagnostics live outside the generated workspace and Git, under `user://host/games/<game>/runtime/`. Each game open creates a timestamped session containing `session.json` and rotating `events-0001.jsonl` segments; the game-level `retention.json` records retained/expired sessions. Rename closes the writer before moving metadata, then continues the same session at its new path. Closing and reopening starts a new session.

Each captured error, warning, print, or host load event has a UTC timestamp with milliseconds, elapsed time, capture sequence, phase, evaluating attempt, active attempt, and origin/attribution when known. Every load attempt gets an ID before compilation, including failed loads and snapshot fallback. Unknown message origins stay unknown. Godot supplies file/line and available stack frames; local variables and live game state are not captured. Startup acceptance policy is unchanged.

`read_runtime_log()` summarizes important diagnostics and the latest attempt outcome. Optional `session_id`, `attempt`, `severity`, `limit`, `raw`, and exclusive `cursor` parameters expose earlier sessions and chronological pages. Begin raw pagination with `cursor=0`; continue using `next_cursor` in the same session. Expired cursors fail explicitly. The full response is bounded to 12,000 characters; raw files retain individual occurrences, while summaries group repetitions. Reload results include attempt diagnostics, and the next player turn receives a hidden notice of new errors/warnings not already delivered. A private bridge receipt acknowledges exact occurrences represented by the final response, after Pi receives it; grouped membership is never inferred from first/last sequence bounds. Filtered reads and response trimming never acknowledge omitted diagnostics. Ordinary prints do not trigger notices. Notification tracking is bounded to 1,024 exact ranges per severity and 16 pending receipts; compaction preserves counts conservatively and can cause a clearly labelled duplicate notice rather than suppress unread evidence.

Defaults are 256 KiB segments, 8 MiB per session, 32 MiB per game, 64 indexed sessions, and a 1,024-record capture queue. A background writer batches writes; callbacks do no disk I/O. Queue pressure discards ordinary output first. Retention expiration, queue overflow, and failed writes are reported separately, with bounded recent loss ranges and lifetime totals. Messages over 4,096 characters and traces over 32 frames are explicitly marked truncated. Clean closed sessions with matching metadata, segment names and sizes skip event parsing on reopen; open or inconsistent sessions are scanned for recovery. Damaged JSONL records are reported. A hard crash can still lose buffered records, and a frozen main thread remains outside this diagnostics system's scope.

## Verification

Fast host/core/UI suite:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

Portable host, reliability, and diagnostics suites with isolated application data (Windows or Linux):

```bash
node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe
node --test tests/workspace-paths.test.mjs tests/model-capabilities.test.mjs
```

Full source verification:

```bash
GODOT_BIN=./Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

The full workflow verifies:

1. the self-contained Windows folder and Go launcher tests;
2. fast Godot host/UI/storage behavior;
3. real-window hostile generated-input ownership when `xvfb-run` is available;
4. one real globally installed Pi acceptance run covering normal agent behavior, native compaction/restart, one-time legacy import/runtime deletion, and packaging/discovery;
5. both explicit `GAMESMITH_PI_BIN` resolution and automatic global npm/`PATH` discovery;
6. process-level migration from `GameSmith Host` to `GameSmithHost`.

The deterministic Pi provider fixture is `tools/fake-openai-endpoint/pi-server.mjs`; it requires Node but no `npm install`.
