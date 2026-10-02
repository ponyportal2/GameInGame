# GameSmith

GameSmith is a Godot 4.7 host for creating and iterating on small games by chatting with a coding agent. Every generated game lives in its own Git workspace. Production agent behavior is provided by a globally installed **Pi coding agent** process; GameSmith owns the game library/UI, workspace boundary, Git milestones, Godot reload/verification, readable transcript, logs, and host policy controls.

The integration/test target is `@earendil-works/pi-coding-agent@0.99.2`.

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
npm install -g @earendil-works/pi-coding-agent@0.99.2
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

## Agent activity and tools

Pi streams assistant text and provider-exposed thinking to GameSmith while a turn is running. GameSmith also shows short ephemeral **TOOL** activity snippets. Intermediate activity is not written to the human-readable transcript.

The model receives Pi's built-in coding tools such as `read`, `edit`, `write`, `grep`, `find`, and `ls`. GameSmith's Pi extension adds game-specific tools:

- `delete_path`, `move_path`;
- `git_status`, `git_diff`, `git_log`, `git_commit`;
- `reload_game`;
- `read_runtime_log`.

No shell/bash/PowerShell tool is exposed to the model.

GameSmith verifies completion at Pi's settlement boundary. A text-only `Done` is not accepted when a game-changing request has not produced the required workspace/reload state. Provider retries, model history, reasoning, coding-tool execution, session persistence, and generic compaction semantics remain Pi-owned.

## Library/chat behavior

- **F1** toggles chat.
- **Enter** sends.
- **Shift+Enter** inserts a newline.
- **Escape** closes chat.
- **Return to Library** is disabled and programmatically blocked while Pi is working.
- While chat is open, GameSmith owns input: generated processing and generated `Control` mouse interception are suspended, captured mouse mode is released, and the prior gameplay input state is restored when chat closes.

Settings is rendered as a host-owned in-canvas overlay above generated-game CanvasLayers.

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

## Verification

Fast host/core/UI suite:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
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
