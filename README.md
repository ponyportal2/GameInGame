# GameSmith

GameSmith is a Godot 4.7 host for creating and iterating on small games by chatting with an LLM agent. Every generated game lives in its own Git workspace, the agent can only use structured workspace/Git/reload/log tools, and successful code changes are hot-reloaded without restarting the host.

## Windows: run from this GitHub checkout

Double-click **`GameSmith.exe` in the repository root**.

The root launcher runs this source tree directly. It first looks for:

```text
runtime\Godot_v4.7.2-stable_win64.exe
```

If that executable exists, **no runtime download is attempted**. If it is genuinely missing, `launch-gamesmith.ps1` downloads the official Godot 4.7.2 x64 ZIP, verifies SHA-256 `731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`, extracts it under `runtime/`, and launches `project.godot`. The runtime directory is ignored by Git because the Godot GUI executable is larger than GitHub's normal per-file Git limit.

Git for Windows must be available on `PATH` for generated-game repositories.

Linux/development launch:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path .
```

The older release-package bootstrapper and its unit tests remain under `tools/windows-bootstrap/`; the source-checkout launcher is documented under `tools/windows-repo-launcher/`.

## Settings

Use **Settings** from either the library or an open game's chat toolbar. Current global controls are:

- provider and model;
- optional Custom OpenAI-compatible `/v1` base address;
- provider API key;
- `reasoning_effort` (`Provider default` omits the field);
- **Agent action limit per request**, default **150**, configurable from 1 to 500.

Supported adapters in this build are OpenRouter, OpenCode Go, Command Code (OpenAI-compatible routes), and a Custom OpenAI-compatible provider. The Custom provider can be used without an API key for local servers.

OpenAI subscription authentication remains behind the provider abstraction rather than being faked: the ChatGPT subscription path is not a plain embeddable API-key endpoint.

## Library/chat behavior

- **F1** toggles chat.
- **Enter** sends.
- **Shift+Enter** inserts a newline.
- **Escape** closes chat.
- **Return to Library is disabled and programmatically blocked while the agent is working.** This prevents abandoning a live tool/reload sequence halfway through a request.
- While chat is open, GameSmith owns input: generated processing and generated `Control` mouse interception are suspended, captured mouse mode is released, and the prior gameplay input state is restored when chat closes.

The library and chat toolbars intentionally use compact action buttons rather than full-height controls. Global **Logs** and **Settings** are available directly from the library; per-game **Folder**, **Logs**, and **Settings** are available in chat.

## Data and logs

The writable application directory is now named **`GameSmithHost`** (no space).

On Windows this is normally:

```text
%APPDATA%\Godot\app_userdata\GameSmithHost\
```

On first launch after upgrading from v1.4 or earlier, GameSmith copies missing files from the old sibling `GameSmith Host` directory into `GameSmithHost`. Existing new-directory files win, and the old directory is deliberately left untouched as a safety copy.

Important paths:

- `user://games/<game>/` — generated game workspace and Git repository;
- `user://host/games/<game>/` — transcript, provider-visible conversation, metadata, last-working snapshot, and **`gamesmith.log`**;
- `user://host/credentials.json` — provider credentials outside all game workspaces;
- `user://logs/gamesmith-app.log` — **global GameSmith log**.

Use **Logs** in the library to open the global log folder, or **Logs** inside a game's chat to open that game's host-data/log folder. These logs record high-level app/agent/provider/tool/reload/navigation events and are bounded in size. Authorization/API-key-like values are redacted before writing so the files are safer to share for debugging.

## Conversation persistence and caching

Each game stores a provider-visible JSONL conversation containing user messages, assistant messages, tool calls, and tool results. The system prompt is static and prior messages are replayed unchanged before each new user message, giving compatible providers a stable prefix for prompt caching. Restarting GameSmith and reopening the same game restores that provider-visible conversation. Older readable-only transcripts are migrated once when no provider conversation exists yet.

## Verification

Fast in-process suite:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

Full source verification:

```bash
GODOT_BIN=./Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

The full workflow verifies the deterministic root Windows launcher, the Go runtime-bootstrap unit tests (when Go is installed), fast agent/runtime/storage tests, a windowed hostile-generated-input regression (when `xvfb-run` is present), real OpenAI-compatible `/v1/chat/completions` traffic through the production HTTP adapter, two-process durable conversation replay, and a process-level migration from the old `GameSmith Host` app-data directory to `GameSmithHost`.

The fake-v1 acceptance server is under `tools/fake-openai-endpoint/`; GameSmith-specific orchestration is documented in `tools/testing/README.md`. The server requires Node but no npm install for the GameSmith scripted workflow.
