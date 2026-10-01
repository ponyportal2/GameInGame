# GameSmith

GameSmith is a Godot 4.7 host for creating and iterating on small games by chatting with an LLM agent. Every generated game lives in its own Git workspace, the agent can only use structured workspace/Git/reload/log tools, and successful code changes are hot-reloaded without restarting the host.

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

Clone/download the repository, open `GameSmith-Windows`, and double-click **`GameSmith.exe`**. There is no release ZIP to unpack.

The bundled Godot runtime means normal startup requires **no Godot download**. The launcher still contains the verified download path as a recovery fallback if someone deletes the bundled runtime.

The Godot runtime is larger than GitHub's normal 100 MB Git-object limit, so that one file is stored with **Git LFS**. A Git clone with Git LFS resolves it to the real executable; browser-generated source archives depend on the repository's Git LFS archive setting.

Git for Windows must be installed and available on `PATH` for generated-game repositories.

Linux/development launch:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path .
```

The release launcher source and unit tests remain under `tools/windows-bootstrap/`.

## Settings

Use **Settings** from either the library or an open game's chat toolbar. Current global controls are:

- provider and model;
- optional Custom OpenAI-compatible `/v1` base address;
- provider API key;
- `reasoning_effort` (`Provider default` omits the field);
- **Agent action limit per request**, default **150**, configurable from 1 to 500.

Supported adapters in this build are OpenRouter, OpenCode Go, Command Code (OpenAI-compatible routes), and a Custom OpenAI-compatible provider. The Custom provider can be used without an API key for local servers.

OpenAI subscription authentication remains behind the provider abstraction rather than being faked: the ChatGPT subscription path is not a plain embeddable API-key endpoint.

## Live agent activity

While an agent turn is running, chat can show ephemeral **AGENT**, **TOOL**, and **THINK** snippets. These are *intermediate activity messages*, not token streaming: each appears after a provider response arrives and before/while its tool work is executed.

- **AGENT** shows short assistant text that accompanied tool calls.
- **TOOL** shows the tool name plus a short argument preview.
- **THINK** is shown only when the provider explicitly exposes reasoning as a plain string (for example `reasoning_content` or `reasoning`). Null, structured, or unknown reasoning payloads are ignored.
- Snippets are not persisted to the readable transcript and are not inserted into future provider context.
- User/model/tool text is escaped before RichTextLabel BBCode parsing, so generated text such as `[color=red]` is displayed literally rather than interpreted as UI markup.

## Agent file-tool behavior

GameSmith keeps the model-facing file tools deliberately small. The current read/edit contract follows the useful parts of Pi/OMP-style coding-agent tooling without importing their shell or full patch languages:

- `read_file(path, offset?, limit?)` returns a bounded **line window** (default 300, max 1000) with `line_start`, `line_end`, `total_lines`, `truncated`, and `next_offset`.
- A truncated read is explicitly a preview. The agent is instructed to continue with `next_offset` or use `search_text`.
- `patch_file` requires one exact unique match **against the complete file on disk**. It never edits the truncated read preview.
- `write_file` is explicitly described as a complete overwrite and is reserved for new files or intentional full rewrites.

This separation matters for large generated scripts: preview truncation can never silently truncate the persisted file during a surgical patch.

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

Each game keeps the **full append-only raw agent trace** on disk, including user messages, assistant messages, tool calls, and tool results. Provider replay is deliberately more compact: completed historical turns are deterministically reduced to the exact user request plus the final assistant response, while the current active tool loop retains its full tool calls/results.

This is cache-friendly by construction: the system prompt and tool schema are stable, no timestamps/session IDs are injected into the provider-visible prefix, completed historical turns remain byte-stable, and each new turn appends after that stable prefix. Compatible providers can therefore reuse prompt-prefix caches. Actual cache eligibility, minimum prefix size, billing, and lifetime still depend on the selected provider/model.

Restarting GameSmith and reopening the same game reconstructs the same compact provider history from the durable raw conversation. Older readable-only transcripts are migrated once when no provider conversation exists yet.


## Provider failures and debug logs

Provider calls now distinguish **transport failures** (timeout, DNS, connection, TLS, no response) from real HTTP status codes. The default provider request timeout is **300 seconds** so slower reasoning models are not mislabeled as `HTTP 0` after 90 seconds.

Per-game logs include a safe provider request/response diagnostic line with the sanitized endpoint, model, timeout, message/context size, transport result, HTTP status, elapsed time, response size, finish reason/token usage when supplied, and safe request-ID/server headers. Authorization/API-key values and URL query strings are not logged.

If a model repeatedly replies with progress text/`Done` without using tools for a game-changing request, GameSmith now stops after **3 consecutive verifier rejections** instead of potentially burning the full agent action budget. Those internal verifier nudges are ephemeral and are no longer written into durable model history. Old persisted verifier pollution is filtered when conversation history is replayed, and interrupted prior turns get one explicit recovery marker before a new request.

For debugging, share the per-game `gamesmith.log` plus `conversation.jsonl`/workspace snapshot. The per-game log should now be sufficient to tell whether a failure was provider transport, HTTP/API, malformed response, verifier-loop, tool, or reload related.

## Verification

Fast in-process suite:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/test_runner.gd
```

Full source verification:

```bash
GODOT_BIN=./Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

The full workflow verifies the self-contained root Windows folder, the Go runtime-bootstrap unit tests (when Go is installed), fast agent/runtime/storage tests, a windowed hostile-generated-input regression (when `xvfb-run` is present), real OpenAI-compatible `/v1/chat/completions` traffic through the production HTTP adapter, two-process durable conversation replay, and a process-level migration from the old `GameSmith Host` app-data directory to `GameSmithHost`.

The fake-v1 acceptance server is under `tools/fake-openai-endpoint/`; GameSmith-specific orchestration is documented in `tools/testing/README.md`. The server requires Node but no npm install for the GameSmith scripted workflow.
