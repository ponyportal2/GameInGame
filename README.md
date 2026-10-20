# GameSmith

GameSmith is a Godot 4.7 host for creating and iterating on small games by chatting with a coding agent. Every generated game lives in its own Git workspace. Choose **Pi**, **Command-code**, **OpenCode**, **Codex**, **Cline**, **Cursor**, **Grok Build**, **AGY (experimental)**, **Kimi Code**, **Kiro CLI**, **Kilo CLI**, **Copilot CLI**, **Crush CLI**, or **OMP** when creating a game. The globally installed harness owns agent behavior; GameSmith owns the game library/UI, workspace boundary, Git milestones, Godot reload/verification, readable transcript, logs, and host policy controls. Existing games without a harness field continue using Pi.

For an existing game, open **Settings → This game → Coding harness**, choose an installed harness, then **Save**. Wait for the current request to finish or Stop it first. Switching closes the previous backend while preserving the running game, workspace, Git history, readable chat, and each harness's separate native session. Switching back resumes that harness's session; native agent histories are not merged. Reopen settings after switching to see the selected harness's provider/model/compaction controls.

The integration/test target is `@earendil-works/pi-coding-agent@1.0.0`.

Only one GameSmith window can edit a game at a time. Opening the same game in another window still allows viewing and running it, but agent requests, compaction, settings changes, rename and deletion wait until the owning window closes that game. Ownership survives Stop and harness switches and is released automatically if the host exits; it has no expiry timer.

Command-code integration requires the tested `command-code@1.82.1`. Install it with `npm install -g command-code@1.82.1` and configure/sign in through its CLI. GameSmith uses the CLI's selected model and native provider configuration. `GAMESMITH_COMMAND_CODE_BIN` can point to its npm `.cmd` shim, an executable, or its `dist/index.mjs` entry point. Node.js must be on PATH.

Command-code games disable GameSmith's provider/model overrides, API key, reasoning, turn limit, model-call delay, and retained-context policy. GameSmith's automatic compaction threshold and Compact now remain available for Pi and Command-code, along with rendered-test permission and automatic reload approval. Saving Command-code settings preserves Pi/provider settings.

The Command-code adapter keeps one persistent native ACP backend for ordinary turns and `/compact`, with incremental reply/reasoning/tool updates. Reopen and Stop resume the explicit per-game native session; readable UI transcripts do not reconstruct native history. Native sessions remain in Command-code's own storage, with references under `host/games/<game>/command-code/`. GameSmith's threshold is checked before a player request and after its completed turn, including cached context. A threshold of 0 disables this host trigger while leaving native automatic compaction intact. Compact now uses the same backend. Native model, retained context, and fast/default compaction policy remain configured in Command-code. No-op and failure outcomes are reported separately.

ACP uses the same unattended permission mode as the former headless transport, after GameSmith verifies its private mod. Command-code 1.82.1 still ignores root `--mod` for ACP, so GameSmith installs an inert loader in the native user mod directory at `~/.commandcode/mods/gamesmith-acp-loader-v1.ts`, active only for marked GameSmith launches. This file remains after uninstalling GameSmith; it is inert outside those launches. If the path already contains different contents, GameSmith refuses to start Command-code rather than overwriting it. A fresh launch nonce verifies mod readiness, then a private native command independently verifies the exact session tool allowlist before inference. Initialization has a 20-second integration deadline; model turns and compaction have no general request timeout.

The mod exposes only native file/search tools and GameSmith game/Git tools, blocks shell/delegation/discovery tools, and checks workspace paths, links and reserved `.git` writes. **Known 1.82.1 limitation:** Command-code still includes an unfiltered “Additional tools” catalog in its system prompt. Disabled tools are absent from the actual callable schemas and remain blocked, but the model may see their descriptions and waste a turn attempting them. No supported ModApi option removes that catalog. Native 1.82.1 also continues tool execution after an uncaught mod-hook exception: the entire GameSmith guard therefore catches unexpected failures and returns an explicit denial. Provider-boundary regressions verify actual outgoing tool schemas and GameSmith instructions, independently of the readiness record. This is a cooperative coding policy, consistent with the existing host policy. Reload waits for player approval unless automatic approval is enabled. Stop retires the backend and preserves native history.

ACP sessions are bound to their original workspace path. Games with saved Command-code history cannot be renamed until **Start new Command-code session** is confirmed in Settings. Reset archives the old reference while preserving chat/game files; rename is then available before the next native session starts. Missing native sessions fail before inference and offer this same recovery path.

Command-code regressions: `node --test tests/command-code.test.mjs tests/command-code-acp.test.mjs`; lifecycle and compaction tests are in the host suite. Set `GAMESMITH_TEST_COMMAND_CODE_BIN` to the tested CLI and run `node --test tests/command-code-native.test.mjs` for actual provider-boundary tests against an isolated local mock provider. To test your selected model live: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe command_code_integration_runner.gd`. This contacts your configured provider and covers editing, headless testing, streaming, backend reuse, reopen, a 65-second reload approval wait, and Stop/resume.

OpenCode integration is tested with installed `opencode 1.19.0`. Install it with `npm install -g opencode-ai`, configure its model/provider in the OpenCode CLI, then select **OpenCode** for a new game. Node.js must be on PATH. `GAMESMITH_OPENCODE_BIN` can point to the executable or npm shim. GameSmith disables provider/model overrides, credentials, reasoning, turn limits, call delay, automatic compaction threshold, retained-context policy, and Compact now for OpenCode games. Saving host testing/reload settings preserves those disabled settings.

The OpenCode adapter retains one authenticated loopback `opencode serve` backend while a game is open. Messages use its native HTTP/SSE API; live reasoning, assistant text and running tools appear immediately, with final snapshots deduplicated. Each game uses a separate explicit native session ID under `host/games/<game>/opencode/session.json`. Reopening resumes that ID; global last-session continuation is never used. OpenCode owns its native history, caching, model/provider configuration and automatic compaction. Current context counts come from the latest native step usage, including cache and reasoning tokens.

GameSmith's tools are exposed through a local [native MCP server](https://docs.opencode.ai/docs/mcp-servers/) as `gamesmith_reload_game`, `gamesmith_start_test_game`, and the other game/Git tools. A [native plugin](https://docs.opencode.ai/docs/plugins/) validates native read/write/edit/apply_patch/search paths, rejects workspace escapes and reserved `.git` edits, and blocks shell/delegation/other unsupported tools at execution. Native tools remain registered: hiding them with deny permissions can make OpenCode's free provider reject requests. This is the same cooperative workspace policy as the other adapters, not a sandbox. Reload keeps the host approval/auto-approval flow. MCP progress notifications keep pending approvals alive across OpenCode's request deadline; Stop calls native session abort and waits for cancellation before accepting another message, retaining the backend and conversation. Closing the game kills the complete adapter/backend/MCP process tree. Windows resolves the Chocolatey shim to its native executable so a transient launcher cannot orphan the backend. Native tool failures include host diagnostics so the agent can repair and retry during the same request.

OpenCode regressions: `node --test tests/opencode.test.mjs tests/opencode-server.test.mjs`; UI and deterministic lifecycle tests run in the host suite. Live acceptance: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe opencode_integration_runner.gd`. This creates isolated GameSmith application data, contacts the CLI's configured/default provider, checks editing, headless testing, same-session resume, and holds reload approval for 65 seconds before approving it. Native Stop acceptance: run the same command with `opencode_stop_runner.gd` to verify cancellation at reload approval, conversation/backend reuse, and process cleanup. The runner isolates OpenCode data as well; use the normal app for your existing native configuration.

If native OpenCode cancellation stalls, Stop gives it five seconds to settle before terminating the adapter, backend and MCP process tree. Normal model requests have no host deadline. Completed HTTP replies supply the canonical final text; missing SSE suffixes are filled in and corrected replies refresh the transcript. Process-tree cleanup also covers detached backend groups on Linux.

Codex integration is tested with installed `codex-cli 0.162.1`. Install/sign in/configure through the Codex CLI, then choose **Codex** when creating a game or switching an existing game. Node.js and `codex` must be on PATH; `GAMESMITH_CODEX_BIN` can select an executable or npm shim. GameSmith disables its provider/model, credentials, reasoning, turn limit, call delay, and all compaction controls for Codex. Saving host reload/testing preferences preserves those disabled settings. Production does not select a model or reasoning effort and does not change Codex's global configuration.

The adapter keeps one native [Codex app-server](https://developers.openai.com/codex/app-server) over stdio while the game is open. Turns use an explicit thread ID saved under `host/games/<game>/codex/session.json`; reopening and switching back resume that thread. Codex owns native history, caching, and automatic compaction. Assistant text and available reasoning deltas stream to chat; completed item snapshots reconcile the saved answer. Normal requests have no GameSmith timeout. Stop uses native turn interruption and retains a healthy backend; a five-second grace bounds stalled initialization, interrupt requests, and turn settlement. Closing or switching kills the complete backend tree on Windows and Linux.

GameSmith file and game tools are registered as native dynamic tools with the `gamesmith_` prefix. File tools provide bounded text reads, exact unique edits, writes, directory listings and literal search. They reject workspace escapes, linked escapes, and reserved `.git` writes. The same test/reload/Git bridge and player approval rules apply as for other harnesses. Native shell, delegation, external plugins/apps/MCP tools and native write approvals are disabled for this runtime; Codex runs with a read-only native sandbox and writes through the bounded GameSmith tools. This remains a cooperative coding policy, not a sandbox for generated game code.

Codex regressions: `node --test tests/codex.test.mjs tests/codex-server.test.mjs`; creation, switching, ownership and deterministic lifecycle tests run in the default host suite. Live acceptance uses `codex_integration_runner.gd` and contacts the signed-in provider. `tools/testing/codex-luna-launcher.mjs` is a test-only launcher selecting `gpt-6-luna` with `xhigh`; set `GAMESMITH_CODEX_BIN` to its absolute path and retain your normal `CODEX_HOME` when using the isolated host runner. The live runner checks actual native model/effort, editing, headless testing, same-backend reuse, reopen history, reload approval and native Stop/resume. It leaves global Codex settings unchanged.

Failed Codex initialization closes the backend and retires the adapter after delivering the error. The next message starts a clean runtime. A failed thread resume keeps the saved thread reference and provides recovery guidance. Retry a transient failure; if you want a fresh conversation, use **Settings → This game → Start new Codex session** and confirm. GameSmith archives the previous `session.json` reference as `session.previous-*.json`, preserves native Codex history, readable chat and files, and starts a new thread on the next message. Existing native threads retain their original dynamic-tool registry; tool changes will require a deliberate compatibility decision.

Cline integration targets installed `cline 3.0.70`. Install with `npm install -g cline`, sign in and select your model through Cline, then choose **Cline** when creating or switching a game. Node.js and `cline` must be on PATH; `GAMESMITH_CLINE_BIN` can select a native executable, npm shim, or JavaScript entry point. GameSmith leaves model, provider, credentials, reasoning and compaction with Cline and disables those overrides for Cline games. Host testing and automatic reload approval remain available. The adapter reads Cline's saved model/reasoning selection because this CLI's ACP defaults otherwise differ from its interactive settings; it never writes those settings or copies credentials to GameSmith files. API-key providers receive their saved key only in the child process environment.

One persistent `cline --acp` process exchanges native JSON-RPC over stdio. Messages reuse the same explicit session; reopening or switching back loads that session from per-game native storage under `host/games/<game>/cline/native/`. The reference is `cline/session.json`. Assistant and available thought/tool updates stream to chat. Cline owns native history, caching and compaction; ACP does not currently report token usage, so GameSmith does not invent a context count. Provider credentials remain in Cline's original store, including native refresh. The runtime uses a private MCP registry without modifying your normal MCP settings. No model request deadline is imposed; native cancellation retains a healthy backend, with the same five-second Stop fallback and process-tree cleanup as other harnesses.

The bounded GameSmith workspace and game/Git tools are exposed through native MCP as `gamesmith__read`, `gamesmith__write`, `gamesmith__start_test_game`, `gamesmith__reload_game`, etc. Native filesystem, shell, terminal and delegation requests are denied. Because Cline's MCP requests have a finite deadline, player reload approval is obtained through the native ACP permission step before MCP execution starts. A single-use, operation-bound host grant authorizes the subsequent reload; stale grants cannot reload the game. Approval does not execute code and has no timer. Failed reloads remain native tool failures with diagnostics for repair. This is a cooperative agent policy, not a sandbox for generated game code.

ACP permission must match a pending tool call announced during the current operation, with a unique call ID, matching input and MCP tool kind. Unmatched, reused, completed or conflicting calls are rejected before reload approval. Programmatic `name` is authoritative when provided. Cline 3.0.70 omits that optional field, so compatibility still relies on its native tool-title formatter for the name, together with the call-ID/input/kind checks. This does not defend against a compromised native ACP backend.

Initialization failures retire the backend so the next request can retry. Failed session loading preserves the saved reference and provides **Settings > This game > Start new Cline session** recovery, with confirmation and archival of the previous reference. Native chat and game files remain intact.

Cline regressions: `node --test tests/cline.test.mjs tests/cline-server.test.mjs`; UI, switching, ownership and deterministic lifecycle checks run in the default host suite. Live acceptance: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe cline_integration_runner.gd`. The host runner isolates HOME, so set `CLINE_PROVIDER_SETTINGS_PATH` to your normal Cline `data/settings/providers.json` first (and `CLINE_GLOBAL_SETTINGS_PATH` if needed). The test contacts your selected free model and checks real editing, headless testing, conversation/backend reuse, reopening, reload approval held for 65 seconds, and native Stop/resume.

Cursor integration targets Cursor Agent CLI `2026.10.01-e373342`. Install the [Agent CLI](https://cursor.com/docs/cli/installation) and sign in with `cursor-agent login`. The desktop app alone does not supply the CLI. Choose **Cursor** for a new game or in **Settings > This game > Coding harness**. GameSmith discovers the standard Windows `%LOCALAPPDATA%/cursor-agent` installation and uses its bundled Node runtime; `GAMESMITH_CURSOR_BIN` can select an installed shim, executable or JavaScript entry point. It does not mistake an unrelated `agent` executable for Cursor. Node.js remains required for the GameSmith adapter and MCP bridge.

A persistent native ACP backend streams assistant and available thought/tool updates. Ordinary messages reuse that process and the explicit native session; reopening or switching back loads the saved reference in `cursor/session.json`. Cursor owns native history, caching, model/provider/reasoning and compaction; GameSmith disables its overrides and leaves Cursor's global settings intact. Host testing and automatic reload approval remain editable. ACP does not supply token usage here, so no context count is invented.

**Cursor uses Auto (`default[]`) in GameSmith.** This is the native ACP default for the tested CLI version. GameSmith does not synchronize the model selected in the desktop editor or interactive CLI, read a saved model choice, pass `--model`, or send `session/set_model`. Selecting a model elsewhere in Cursor does not guarantee that this integration uses it. Native provider/reasoning/compaction behavior remains Cursor-owned; GameSmith does not expose model overrides or write Cursor's global settings. The effective model reported by ACP is recorded in the game's `cursor/backend.json` for diagnosis.

GameSmith supplies its bounded workspace and game/Git tools through MCP. Permission must match a current, single-use call ID and the announced structured `rawInput.providerIdentifier`/`toolName`/arguments; display titles cannot authorize tools. Native filesystem/shell and external MCP access is denied by project permissions in a private host working directory, without editing the game's or your global Cursor configuration. Reload approval waits through ACP before the finite MCP call begins; the subsequent reload consumes an operation-bound host grant. This is cooperative agent policy, not a sandbox for generated GDScript.

Stop cancels the native turn and retires the backend process tree, with a five-second fallback if cancellation stalls. The next message resumes the same conversation in a fresh backend. This clears Cursor's cancelled MCP execution queue; ordinary messages remain persistent. Readiness failures retire the backend for a clean retry. An unresumable reference is preserved with **Settings > This game > Start new Cursor session** recovery and confirmation/archive.

Cursor regressions: `node --test tests/cursor.test.mjs tests/cursor-server.test.mjs`; lifecycle, switching and ownership run in the default host suite. Live acceptance: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe cursor_integration_runner.gd`. For this isolated Windows test, first set `$env:GAMESMITH_TEST_NATIVE_APPDATA = $env:APPDATA`, `$env:GAMESMITH_CURSOR_BIN = "$PWD/tools/testing/live-cursor.mjs"`, and `$env:CURSOR_CONFIG_DIR = "$env:USERPROFILE/.cursor"` so the native CLI can use its normal saved login while Godot's test data remains isolated. It checks editing/headless testing, streaming, process/history reuse, reopen, approval held for 65 seconds and Stop/resume. Set `GAMESMITH_TEST_CURSOR_MODEL=default[]` to assert the tested ACP Auto/default on creation, reopen and Stop/resume. With no expected ID, the runner only checks that ACP reports a model; that is not an inheritance test.

Grok Build integration targets the installed CLI `1.0.52`. Sign in and configure Grok Build natively, then choose **Grok Build** when creating a game or under **Settings > This game > Coding harness**. It uses `grok agent --no-leader stdio` over ACP, with native-tool restrictions. Discovery uses `grok` or the standard Windows `%USERPROFILE%/.grok/bin/grok.exe`; `GAMESMITH_GROK_BUILD_BIN` can specify another executable or JavaScript wrapper. Neither harness falls back to the ambiguous `agent` command. ACP initialization must advertise Grok's native identity for Grok Build, or Cursor's native login method for Cursor; mismatched overrides are rejected before opening a conversation.

Ordinary Grok Build turns reuse one backend and native session. Reopening, switching back and sending a message after Stop load the explicit reference in `grok-build/session.json`. Model/provider/reasoning and compaction remain native-owned; GameSmith's overrides are disabled, while host testing and reload preferences remain available. The effective native model is recorded in `grok-build/backend.json`. Grok owns persistence and prompt caching; GameSmith does not promise provider cache hits.

GameSmith supplies workspace/game/Git tools through MCP. Native tools are limited to MCP discovery/invocation, with shell, file access, delegation and web tools removed or denied. Permission approval requires the current unique ACP call ID, stable `x.ai/tool` metadata identifying `use_tool`, and structured `tool_name=gamesmith__<known command>` plus unchanged `tool_input`; display titles never grant authority. External MCP invocation is rejected. Reload approval uses the same single-use host grant as Cline/Cursor and can wait for the player before the MCP execution window begins. Stop cancels and retires the backend tree, with a five-second fallback, then the next message resumes native history. Readiness failures retire for retry; an unresumable reference is kept with **Start new Grok Build session** confirmation/archive recovery.

Grok Build regressions: `node --test tests/grok-build.test.mjs tests/grok-build-server.test.mjs`; `grok_build_lifecycle_runner.gd` runs in the default host suite. Live Windows acceptance: set `$env:GAMESMITH_TEST_NATIVE_USERPROFILE=$env:USERPROFILE`, `$env:GAMESMITH_GROK_BUILD_BIN="$PWD/tools/testing/live-grok-build.mjs"`, and `$env:GAMESMITH_TEST_GROK_BUILD_BIN="$env:USERPROFILE/.grok/bin/grok.exe"`, then run `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe grok_build_integration_runner.gd`. This uses the normal native login/model while keeping Godot test data isolated; it checks game tools, history/process reuse, reopen, delayed reload approval and Stop/resume.


## AGY CLI — experimental

AGY (Antigravity CLI) support targets installed CLI **1.3.4** and is **experimental**. Choose **AGY (experimental)** for a new game or under **Settings → This game → Coding harness**. Discovery uses `agy`, the standard Windows `%LOCALAPPDATA%/agy/bin/agy.exe`, or `GAMESMITH_AGY_BIN`. Sign in and select your model natively; GameSmith does not pass model, provider, reasoning or compaction overrides. Those settings are disabled for AGY games; host test/reload preferences remain available.

The adapter uses native [persistent stream-JSON](https://antigravity.google/docs/cli/headless/) with one backend for ordinary turns and saves the explicit conversation ID in `agy/session.json`. Reopen, switching back, error recovery and Stop resume with `--conversation <id>`, never the globally most recent conversation. Streamed text is reconciled with the final native answer. Cumulative conversation token totals are not reported as current context size. Stream-JSON has no cancellation command, so Stop terminates the backend/MCP tree; the next message resumes the saved conversation. Failed resume keeps the reference and readable chat, with **Start new AGY session** confirmation/archive recovery in Settings.

GameSmith prepares a private `.agents/agents/gamesmith.md` with its game instructions and MCP server, plus a [PreToolUse hook](https://antigravity.google/docs/hooks). The hook checks the current conversation, exact `call_mcp_tool` identity, `ServerName=gamesmith`, and a known `ToolName`; native filesystem/shell/browser/delegation and external MCP requests are denied by that policy. The MCP adapter separately rejects idle calls and enforces the shared workspace boundary. Reload waits for ordinary host approval (or the player's automatic approval preference). Global native configuration is not edited. **Actual native hook execution and model-driven MCP calls remain unverified** because inference is unavailable; this is not a claim of tested native tool isolation.

Verification: deterministic Node and Godot fixtures cover streaming/final reconciliation, MCP edits/headless tests/reload approval, process reuse, explicit resume, ownership, reset, failures and Stop. Installed AGY successfully discovered the GameSmith MCP tools and resumed the same conversation ID, then returned `FAILED_PRECONDITION: User location is not supported for the API use` on both attempts. **No successful model invocation or live generated-game acceptance has been performed.** Run `node --test tests/agy.test.mjs tests/agy-server.test.mjs` and `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe agy_lifecycle_runner.gd` for fixture verification.

## Kimi Code CLI

Kimi Code integration targets the native **2.1.1** CLI (`kimi acp`), not the separate Python Kimi CLI. Select your model/provider in Kimi Code, then choose **Kimi Code** for a new game or under **Settings > This game > Coding harness**. Discovery checks `%USERPROFILE%/.kimi-code/bin/kimi.exe` on Windows, `~/.kimi-code/bin/kimi` elsewhere, and `kimi` on PATH; `GAMESMITH_KIMI_BIN` selects another executable. Node.js is required for the adapter/MCP bridge. GameSmith does not override model, provider, credentials, reasoning, permission defaults or compaction; native agent settings are disabled in GameSmith while host testing/reload controls remain available.

A persistent [ACP stdio server](https://moonshotai.github.io/kimi-code/en/reference/kimi-acp.html) reuses one native session for ordinary messages. Reopening and returning after Stop load the explicit ID in `kimi/session.json`; the native history remains in Kimi's original data store. Model credentials are inherited without copying or editing global configuration. `kimi/backend.json` records the effective native model. Current context usage comes from ACP `usage_update`, including updates emitted after the final response; native history, compaction and provider caching remain Kimi-owned. Stop sends native cancellation, retires the backend/MCP tree and uses the shared five-second fallback if cancellation hangs. An unresumable saved reference is preserved with **Start new Kimi session** confirmation/archive recovery in Settings.

The adapter writes a private [default agent profile](https://moonshotai.github.io/kimi-code/en/customization/agents.html) with an exact GameSmith MCP tool allowlist. Kimi enforces this list before execution, excluding native shell/files/delegation and other MCP tools. This native restriction is the policy boundary: Kimi 2.1.1 supplies structured tool arguments only after permission approval, so the ACP client binds approval to a current, single-use call ID and `kind=other`, without trusting a display title for identity. The MCP bridge separately rejects idle calls and enforces workspace boundaries. Reload uses ordinary GameSmith approval, with MCP progress and an extended native tool deadline to accommodate human waits. This is cooperative tool policy, not a sandbox for generated game code.

Run `node --test tests/kimi.test.mjs tests/kimi-server.test.mjs` and the default Godot host suite for deterministic verification. Live selected-model acceptance: set `$env:KIMI_CODE_HOME="$env:USERPROFILE/.kimi-code"` and optionally `$env:GAMESMITH_TEST_KIMI_MODEL` to the expected native alias, then run `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe kimi_integration_runner.gd`. The explicit home preserves native credentials while Godot test data is isolated. The runner exercises editing, headless testing, native model inheritance, backend/history reuse, reopening, a 65-second approval wait and Stop/resume. Installed Kimi 2.1.1 passed this live runner with the inherited selected `openrouter/poolside/laguna-s-2.1:free` model on the second attempt; the first attempt hit native HTTP 429 retries and remained partial. Deterministic and packaged-fixture checks also pass. Recorded results and limitations are in [TODO-kimi.md](docs/todos/TODO-kimi.md).

## OMP (Oh My Pi)

Choose **OMP** when creating a game or under **Settings > This game > Coding harness**. Tested with **OMP 18.10.3**, installed through [Oh My Pi's official instructions](https://github.com/can1357/oh-my-pi). Discovery uses `omp` on PATH; `GAMESMITH_OMP_BIN` selects another executable. Node.js is required for the adapter. Sign in and select your model in OMP itself. GameSmith inherits native settings and `PI_CODING_AGENT_DIR` (normally `~/.omp/agent`); model/provider/reasoning/compaction controls are disabled for OMP games, while host reload/testing controls remain available.

OMP reuses GameSmith's bounded workspace tools, host bridge, editing ownership and Stop/reset lifecycle. Its native RPC and extension APIs differ from Pi, so it uses its own small transport and policy extension. One persistent `omp --mode rpc` process streams text/reasoning and reuses an explicit native JSONL conversation. Native tools, discovered extensions/skills/rules and LSP are disabled for this private run. Exactly 17 GameSmith host tools are registered and activated; a fresh nonce-bound policy readiness check must succeed within 30 seconds before player inference. The independent shared workspace layer enforces path/symlink and Git boundaries. Native MCP discovery may start configured servers, but their tools cannot be invoked through the restricted active set and tool guard.

Native history lives under each game's `omp/native/sessions`. The explicit `omp/session.json` reference survives reopen, rename and Stop; saved references are never silently replaced when resume fails. **Start new OMP session** in Settings confirms and archives the reference, preserving game files, readable chat and old native history. Native backend exit retires the adapter even between messages; the next message starts a fresh backend and resumes the saved conversation. Agent turns consume OMP's separate `session_settled` frame before handing control back, including when the prompt result already reports a settled snapshot. Stop uses native cancellation followed by retiring the backend tree, with the existing five-second forced fallback. Ordinary model turns and player reload approval have no general timeout. Current context usage comes from native session state, rather than cumulative token totals; caching and automatic compaction remain OMP-owned.

Run `node --test tests/omp.test.mjs tests/omp-server.test.mjs` for policy and assembled-runtime tests. `omp_lifecycle_runner.gd` is part of the normal host suite. Live acceptance: set `GAMESMITH_TEST_OMP_MODEL` to the expected native model, then run `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe omp_integration_runner.gd`. The runner preserves native login while isolating Godot data and verifies editing, headless testing, streaming, exact tool activation/model inheritance, history/backend reuse, reopening/rename, a 65-second reload approval and Stop/resume. Evidence is recorded in [TODO-omp.md](docs/todos/TODO-omp.md).

## Crush CLI

Choose **Crush CLI** when creating a game or under **Settings > This game > Coding harness**. Install from [Charm's official instructions](https://github.com/charmbracelet/crush/blob/v0.96.1/README.md), for example `winget install charmbracelet.crush` on Windows. The adapter supports **Crush CLI 0.96.1**; other versions fail before inference until their native tool registry is verified. Node.js is required. Discovery uses `crush` on PATH; `GAMESMITH_CRUSH_BIN` selects a custom executable. Restart GameSmith after installation so its PATH is refreshed.

Crush owns authentication, model/provider/reasoning selection, caching and compaction. GameSmith inherits native configuration and environment variables, including `CRUSH_GLOBAL_CONFIG`, `CRUSH_GLOBAL_DATA` and `CRUSH_CACHE_DIR`; it neither copies credentials into its private policy nor overrides model settings. Model/provider/compaction controls are disabled for Crush games. `crush/backend.json` records the effective model, provider and reasoning selection. Current context usage is unavailable rather than inferred from cumulative tokens.

Crush runs a temporary HTTP server on a random `127.0.0.1` port without request authentication. Other local processes able to reach that port can access its API; the random port is not an access-control boundary.

Each game uses a persistent private `crush server` with native HTTP/SSE streaming and a native database. Ordinary messages reuse the backend and conversation. The explicit `crush/session.json` reference preserves history across reopening, rename and Stop. GameSmith instructions are native context loaded once per backend; each turn sends only the player message. Initialization failures retire the backend for retry. An unresumable session remains saved with an actionable error; **Start new Crush session** in Settings confirms and archives its reference while keeping game files, readable chat and the old native history. Stop requests native cancellation, retires the process tree and retains the existing five-second forced fallback; there is no general model timeout.

Only exact `mcp_gamesmith_<tool>` tools are enabled. The private highest-priority policy hides all known native filesystem, shell, delegation, web and resource tools, disables external MCP servers and LSP startup, and denies any native permission request. The reused bounded MCP bridge independently checks active host operations, workspace paths and reload approval. Startup waits for MCP discovery before inference. Reload waits for the player or honors automatic approval, including waits longer than 60 seconds. Generated GDScript is not sandboxed.

Run `node --test tests/crush*.test.mjs` for protocol and assembled-runtime regressions. `crush_lifecycle_runner.gd` is in the normal host suite. Real acceptance: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe crush_integration_runner.gd`; optionally set `GAMESMITH_TEST_CRUSH_MODEL` to the expected native model. Crush 0.96.1 passed 24/24 real checks from source and the rebuilt Windows PCK with native `dots-studio/dots-3-note-preview:free` and high reasoning, including editing, headless testing, rename/history, 65-second reload approval and Stop/resume. Results and limitations are recorded in [TODO-crush.md](docs/todos/TODO-crush.md).

## Blender assets (all harnesses)

Blender is optional per game. New games start with **Enable Blender tools** unchecked; enable it during creation or later under **Settings > This game**. When disabled, the agent receives no Blender tool definitions or standing instructions, and direct calls are rejected. Existing games keep their Blender access. Changes wait until the agent and Blender are idle. Saved Codex conversations require explicit confirmation to archive the previous session reference and start a fresh Codex conversation, because their tool lists cannot change; chat and game files are kept.

The shared `blender` tool runs background Blender with `bpy`, renders previews and reports scene contents. Tested with **Blender 5.2.2 LTS**. Install Blender on PATH, use its standard Windows installation, or set `GAMESMITH_BLENDER_BIN` to the executable. Node.js is required. GameSmith does not change harness model/provider settings.

Ask the agent to create or modify a Blender asset. Its standing instructions tell it to fetch `blender(action="guide")`, write a reusable workspace `.py` script, then `start` it with an optional `.blend` input and PNG render path. **Python runs wait for player approval by default**, showing the script path, complete source (UTF-8, at most 256 KiB), SHA-256, and a warning about its permissions. Run executes a private snapshot of those bytes; changes to the original before launch or to the snapshot fail. Cancel returns a tool failure to the agent. Settings ? **Agent & testing** ? **Automatically approve Blender scripts** skips this wait for all harnesses. It defaults off, is saved globally, and is independent of reload approval. Enabling it permits agent-authored Python to run with your user permissions. The agent cannot change this setting or approve its own request. Cline, Cursor and Grok Build wait at ACP permission time before the finite MCP execution window, then consume a private, single-use grant bound to the operation and exact arguments. Imported modules and files read by the script are not frozen. After approval, `start` returns the background job ID; `status` supplies bounded logs, exit status and a scene report. `stop`, the agent's Stop button, and closing the game cancel pending approval and terminate running jobs. Opening/rendering a `.blend` without an explicit Python script does not request Python approval; embedded auto-run scripts stay disabled. The guide covers saving editable `.blend` sources and exporting GLB/PNG assets that Godot can load at runtime without editor imports. It includes an asymmetric export example with named animation pivots and preview-only lighting. Generated games receive a workspace-aware `gamesmith_assets` helper before startup, so runtime GLB/PNG paths survive reloads, separate tests and supported renames. Blender status is compact by default; use `details=true` with `offset`/`limit` for object pages and retained logs. Scene inspection returns exact game-relative paths with bounded recursive `depth`. For visual changes the guide requires checking a rendered Godot screenshot when player settings and model vision permit, in addition to the headless test.

`inspect` returns a PNG as native image tool content, plus dimensions. Actual visual inspection requires image support in the selected harness/model; otherwise the agent must report that limitation and use scene diagnostics rather than claim to have seen the render. Previews are limited to 8 MiB, 4096 pixels per side and four megapixels. Use small CPU renders first, test the resulting game headlessly and reload it before handing it back.

Successful status also preserves bounded warning summaries separately from the rolling log. Scene reports give advisory hints for connected procedural/custom shaders that may lose appearance in glTF; they do not certify export fidelity. The guide includes a UV base-color baking example and multiple preview views from one script. Private jobs disable `.blend1` backups without changing the player's preferences. Render quality and artistic choices remain script-owned.

Blender starts with factory preferences and embedded auto-run scripts disabled. Its environment includes only required OS/display/home variables and private Blender paths; unrelated credentials, `PYTHONPATH`, `NODE_OPTIONS`, and inherited `PATH` are omitted. Input/output arguments and preview reads are checked against the game workspace, including links and protected `.git` paths. **Approved Python scripts still run with your user permissions, including filesystem, process and network access; approval and environment reduction are not a sandbox.** If the supervisor crashes, GameSmith attempts child cleanup using process birth identity and the private job path, never just an old PID. A failed ownership check blocks new jobs rather than killing an unrelated process; `stop` retries cleanup. Existing Codex conversations retain their original dynamic-tool registry: use **Start new Codex session** in Settings to expose Blender in a conversation created before this update. Other running backends should be restarted to load the updated integration.

Deterministic tests: `node --test tests/blender.test.mjs` and `blender_runner.gd` in the host suite. Installed-Blender acceptance: `node tools/testing/verify.mjs --live blender --output errors`.

## GitHub Copilot CLI

Choose **Copilot CLI** when creating a game or under **Settings > This game > Coding harness**. Install with `npm install -g @github/copilot`, then sign in through Copilot. Tested with **Copilot CLI 1.0.96** using its preview [ACP stdio server](https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server). Discovery uses `copilot` on PATH; Windows npm shims are resolved through Node without invoking PowerShell. `GAMESMITH_COPILOT_BIN` selects another executable or JavaScript entry point. Node.js is required.

Copilot owns authentication, model/provider/reasoning selection, caching and compaction. GameSmith does not pass a model or change native model settings; its corresponding settings are disabled. `copilot/backend.json` records the effective native selection. Instructions live in a private GameSmith custom agent profile with a fresh random filename and name for each runtime. GameSmith verifies that ACP selected that exact ID before inference, preventing a personal agent named `gamesmith` from shadowing its profile. After native resume and verified selection succeed, GameSmith removes obsolete generated UUID profiles from its private agent directory; failed initialization preserves them, and unrelated agents are left alone. Each turn sends only the player message.

Ordinary messages reuse a persistent ACP backend and native conversation. An explicit reference in `copilot/session.json` resumes history after reopening or Stop; the readable transcript does not recreate native context. Failed initialization retires the runtime for retry. An unresumable reference is kept with an actionable error; **Start new Copilot session** in Settings asks for confirmation and archives the reference while keeping game files and readable chat. Stop sends native cancellation, retires the backend/MCP process tree and uses the existing five-second forced fallback; there is no general model timeout.

Exact native startup and custom-agent tool lists expose only `gamesmith-<tool>` MCP tools. Native filesystem, shell, delegation and external MCP tools cannot be invoked; all ACP permission, filesystem and terminal requests are denied. Global MCP servers may still start through Copilot configuration, so this is invocation policy rather than process isolation. The reused bounded MCP bridge additionally checks the active host operation, workspace paths and reload approval. Reload waits for the player, or honors GameSmith's automatic approval preference, with an extended native MCP deadline. Generated GDScript is not sandboxed.

Run `node --test tests/copilot*.test.mjs` for deterministic protocol/runtime tests. `copilot_lifecycle_runner.gd` is included in the default host suite. Real acceptance: `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe copilot_integration_runner.gd`; optionally set `GAMESMITH_TEST_COPILOT_MODEL` to the expected native model. Copilot 1.0.96 passed all 24 real acceptance checks with native Auto (`auto`), both from source and from the rebuilt Windows PCK, including headless testing, rename/history continuity, a 65-second reload approval wait and Stop/resume. Evidence and limitations are recorded in [TODO-copilot.md](docs/todos/TODO-copilot.md).

## Kilo CLI

Choose **Kilo CLI** when creating a game or under **Settings > This game > Coding harness**. The adapter is **tested with Kilo CLI 7.8.8** (`npm install -g @kilocode/cli@7.8.8`); other releases have not been verified. Discovery uses `kilo` on PATH; `GAMESMITH_KILO_BIN` selects another executable, npm shim or JavaScript wrapper. Node.js is required. Select your model/provider and sign in through Kilo itself. GameSmith does not override model, credentials, provider, reasoning or compaction; corresponding GameSmith controls are disabled while host testing/reload preferences remain available.

Kilo shares the OpenCode HTTP/SSE transport and workspace-tool policy, with its own `kilo serve` backend, authenticated loopback requests and `KILO_*` configuration. GET/HEAD requests route through `?directory=`, mutating requests use `x-kilo-directory`, and SSE keeps the tested `/event` endpoint. Ordinary messages reuse the backend and explicit native conversation. GameSmith saves the reference in `kilo/session.json`, separately from OpenCode, and records the effective native model in `kilo/backend.json`. Reopening and switching back resume that same native history. Kilo binds native conversations to their original workspace path, so GameSmith rejects renaming any game with saved Kilo history, even while using another harness. Rename before the first Kilo turn. Provider caching and compaction remain native-owned; the readable transcript does not reconstruct history.

If the saved native session cannot resume, GameSmith retires the failed backend and keeps the reference. Use **Settings > This game > Start new Kilo session**, then confirm to archive the old reference while keeping game files and readable chat. Cancelling changes nothing. Reset releases rename protection until the next Kilo message creates fresh native history; rename before that message if needed. The old native conversation is not deleted or included in the fresh conversation.

GameSmith adds workspace instructions, native-tool restrictions and its MCP game/Git tools through per-process configuration. Native file tools remain workspace-bounded; shell, delegation, outside paths and destructive Git metadata access are denied by the shared OpenCode plugin. Reload uses ordinary GameSmith player approval or automatic approval and can wait without a timer. Stop sends native abort and retains a healthy backend; a stalled Stop force-terminates its tree after five seconds, then the next message resumes the explicit session. This is cooperative tool policy, not a sandbox for generated GDScript.

Run `node --test tests/kilo.test.mjs tests/kilo-server.test.mjs` for resolver/transport regressions. Kilo lifecycle, switching, ownership and forced-Stop runners are included in the default host suite. Live acceptance: optionally set `$env:GAMESMITH_TEST_KILO_MODEL` to the expected `provider/model`, then run `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe kilo_integration_runner.gd`. It checks real edits, headless testing, streaming, exact model/history/backend reuse, reopen, rename protection, a 65-second approval wait and Stop/resume. Installed Kilo 7.8.8 passed all 24 live checks with the inherited `kilo/stealth/glyph-cluster` model. All 29 default host runners passed in one uninterrupted run; packaged fixture checks also passed. Verification evidence and limitations are recorded in [TODO-kilo.md](docs/todos/TODO-kilo.md).

## Kiro CLI

Choose **Kiro CLI** when creating a game or in **Settings > This game > Coding harness**. The adapter targets installed **Kiro CLI 2.30.0**, explicitly using `kiro-cli acp --agent-engine v2`. It detects `%LOCALAPPDATA%/Kiro-Cli/kiro-cli.exe` on Windows, `~/.local/bin/kiro-cli` elsewhere, or `kiro-cli` on PATH. `GAMESMITH_KIRO_BIN` selects another executable. Node.js is required. Kiro owns authentication, model, provider, reasoning, compaction and caching; GameSmith's corresponding settings are disabled. Global native configuration is never edited.

New conversations use Kiro's native default. To save a particular model for new sessions, use Kiro's `/model set-current-as-default` or `kiro-cli settings chat.defaultModel <model-id>` ([native model settings](https://kiro.dev/docs/cli/chat/model-selection/)). An interactive session's temporary choice is not a global default. With no saved default, the tested installation reports **Auto**. GameSmith does not pass `--model` or call `session/set_model`; `kiro/backend.json` records the effective native selection. Resumed conversations keep their native model state.

A persistent [ACP stdio backend](https://kiro.dev/docs/cli/acp/) handles ordinary messages without restarting. GameSmith saves an explicit ID in `kiro/session.json`; reopening, renaming and returning after Stop load that same native conversation, including V2's `_kiro.dev/session_file` hint. Native history stays in `~/.kiro/sessions/cli/`, or `KIRO_HOME/sessions/cli/` when configured; GameSmith does not copy or modify it. GameSmith instructions live in the custom agent profile; individual turns contain only the player's message. Failed initialization retires the runtime for a clean retry. An unresumable reference is preserved with **Start new Kiro session** confirmation/archive recovery in Settings. Stop requests native cancellation, retires the backend/MCP tree and uses the shared five-second forced fallback if necessary. No general model timeout is added.

A private `.kiro/agents/gamesmith.json` exposes only exact `@gamesmith/<tool>` selectors and excludes global MCP configuration. Native filesystem/shell/delegation tools are unavailable in that profile. Permission approval requires the current session and single-use announced call ID, unchanged arguments, and matching structured GameSmith MCP server/tool identities from both the announcement and permission request. Display titles and early streaming tool chunks confer no authority. Kiro categorizes MCP file writes as `edit`, so kind is checked for consistency rather than assumed to be `other`. The MCP bridge independently enforces active-operation and workspace boundaries. Reload uses GameSmith's normal approval or the player's automatic approval setting, with an extended native tool deadline for human waits. This is cooperative tool policy, not a sandbox for generated GDScript.

Run `node --test tests/kiro.test.mjs tests/kiro-server.test.mjs` for protocol/transport regressions; `kiro_lifecycle_runner.gd` is in the default host suite. Live acceptance: optionally set `$env:GAMESMITH_TEST_KIRO_MODEL` to the expected native model, then run `node tools/testing/run-host-tests.mjs GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe kiro_integration_runner.gd`. It verifies actual edits, headless tests, streaming, exact history/session/backend reuse, reopen, rename, a 65-second reload approval and Stop/resume. Installed Kiro 2.30.0 passed all 24 live checks with native Auto on the second attempt; the first exposed a permission-kind mismatch fixed with a regression. The isolated packaged fixture also passed all 29 lifecycle checks. Results and limitations are recorded in [TODO-kiro.md](docs/todos/TODO-kiro.md).

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

Pi games expect a global `pi` executable. Install the pinned build with:

```bash
npm install -g @earendil-works/pi-coding-agent@1.0.0
```

On Windows, `GameSmith.exe` checks for Pi, Command-code, OpenCode, Codex, Cline, Cursor, Grok Build, AGY, Kimi Code, Kiro CLI, Kilo, Copilot CLI, Crush CLI, or OMP at startup, including their `GAMESMITH_*_BIN` overrides and the standard Windows Cursor/Grok/AGY/Kimi/Kiro installations. If none is installed, it shows a non-blocking installation warning and still opens GameSmith. Restart after installing a harness. If Pi is installed outside `PATH`, set `GAMESMITH_PI_BIN` to the executable path (for npm on Windows, typically a `pi.cmd` shim).

For development on Linux:

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path .
```

The Windows launcher source and unit tests are under `tools/windows-bootstrap/`.

## Settings

The library is a searchable workspace gallery. Each game's **•••** menu opens its folder, renames it, or asks for confirmation before deletion. In a workspace, project and execution controls sit beside the conversation; **F1** switches between chat and play. The layout adapts to the window size.

Use **Settings** from the library sidebar or an open game's chat toolbar. Preferences are grouped into **Model**, **Agent & testing**, **Conversation**, and **This game** tabs. **Compact now** is on the Conversation tab. Current controls are Pi-oriented:

- global Pi provider and model;
- optional Custom OpenAI-compatible `/v1` base address;
- provider API key passed to Pi;
- Pi thinking/reasoning level;
- **Pi turn limit per request**, default **150**, configurable from 1 to 500;
- **Delay between Pi provider calls**, default **6 seconds**;
- **Automatic compaction threshold (Pi and Command-code)**, default **100,000 current-context tokens**; set to **0** to disable GameSmith's threshold;
- **Recent tokens kept verbatim by Pi compaction**, default **20,000**;
- **Compact now** when a game is open.

OpenRouter, OpenCode Go, Command Code, and Custom OpenAI-compatible routes are mapped into Pi configuration. Custom can be used without an API key for local servers. **OpenAI subscription** delegates to Pi's global `openai-codex` authentication instead of GameSmith implementing a separate subscription token flow.

Per-game provider/model overrides remain available. Saving provider/model/thinking settings restarts only that game's Pi runtime; the generated game itself is not restarted.

Model capabilities come from Pi's installed catalog for exact provider/model matches. Official OpenRouter endpoints also use live provider metadata, including when configured under Custom, so newly published models do not inherit the unknown-model output cap. Public OpenRouter metadata is cached across games for five minutes; failed refreshes do not replace a successful listing. During a refresh outage, previously verified metadata less than seven days old remains usable, with a warning in the Pi runtime log. Without usable cached metadata, discovery falls back to the installed OpenRouter catalog even when the official endpoint is configured under Custom. Unknown models, including arbitrary Custom endpoints, use conservative budgets of **8,192 context tokens** and **1,024 output tokens**, with reasoning disabled. These budgets are not claims about the server's actual limits. Compaction settings never change model capabilities; automatic compaction and retained context are capped to the available budgets.

Important JSON files are replaced through a flushed temporary file. Settings reports any failed writes and stays open so you can retry; a partial save is reported explicitly.

## Agent activity and tools

Pi streams assistant text and provider-exposed thinking to GameSmith while a turn is running. GameSmith also shows short ephemeral **TOOL** activity snippets. Intermediate activity is not written to the human-readable transcript.

The model receives Pi's built-in coding tools such as `read`, `edit`, `write`, `grep`, `find`, and `ls`. GameSmith's Pi extension adds game-specific tools:

- `delete_path`, `move_path`;
- `git_status`, `git_diff`, `git_log`, `git_commit`;
- `reload_game`;
- `read_runtime_log`.

No shell/bash/PowerShell tool is exposed to the model. Host file tools reject paths that cross a symbolic link or junction inside the workspace, omit linked entries from listings and searches, and refuse to write, move or delete reserved `.git` metadata.

Unsuccessful native turns automatically recover after **8, 16, 32 and 64 seconds**, with four retries per player request. This applies to all harnesses after their own retries finish, without trying to classify provider errors. Stop cancels the wait immediately. GameSmith retires the failed backend tree and resumes the saved native conversation; every retry includes the original player request alongside instructions to inspect the current state and preserve completed edits and tool results. Existing history alone does not prove the current request was preserved. Adapters track native admission per operation; uncertain preservation is stated explicitly in the recovery prompt, and unkeyed ACP updates are not treated as proof. This keeps the objective available even when a later request fails before entering an existing native conversation. Abandoned streamed text is removed from visible chat before retrying, preserving durable dialogue and tool records. Recovery messages and intermediate errors stay out of the readable transcript; the status shows the delay, logs retain the errors, and exhaustion reports one final failure. Runtime startup failures and explicit native initialization failures bypass recovery: their actionable error appears immediately, the backend is retired, and Settings session-reset controls become available. Retry those manually after correcting the configuration or resetting a stale session. Provider turn failures still retry without classifying authentication or generation limits. Tool failures remain with the agent to repair; explicit player cancellation, ownership refusal, GameSmith turn limits and failed pre-request compaction do not start recovery.

The harness decides when its turn is complete. All harnesses are instructed to run a successful headless test of the current edits, inspect results and stop the test before requesting `reload_game`, then normally reload before the final player summary. Further edits require another headless test. Discussion-only turns, failed tests, and explicit player requests not to reload are exceptions. This is an instruction to the agent, not a host-enforced test gate. Provider retries, model history, reasoning, coding-tool execution, session persistence, and generic compaction semantics remain harness-owned.

Games always open in chat without executing generated code, so after a game crashes GameSmith you can reopen its chat and ask Pi to repair it. **Run Game** starts execution; **Reload Game** is available in chat and gameplay once a game is running. Both manual controls are disabled while the agent is working. Pi's `reload_game` waits indefinitely for approval: a notice over the game leaves gameplay input and mouse untouched; press **Shift+F5**, or **F1** and click **Allow Reload** in chat. **Stop** cancels the waiting agent. Generated games still share the host process: running broken code can crash GameSmith again.

Run is available only when workspace `main.gd` or a last working snapshot exists. Chat and gameplay show persistent execution status: **Not running**, **Running workspace**, or **Running last working snapshot**. This identifies the loaded source, without claiming it includes later file edits.

For parameter changes, agents can inspect the live generated game and batch-patch existing node properties without reloading. Source edits remain necessary for persistence; loaded code and future-spawn defaults remain unchanged until reload unless the game uses live configuration that can also be patched. See [live runtime tools](docs/runtime-properties.md) for supported values, identity checks, bounds and partial-failure semantics.

**Allow Reload** gives GameSmith permission to attempt loading the game's current workspace, including any edits made while the request was waiting. A reload request does not freeze a revision. To cancel the waiting request, use **Stop**.

Settings → **Agent & testing** → **Automatically approve agent reload requests** skips the approval wait for any harness. It defaults to off and is saved globally. Manual Run/Reload behavior is unchanged.

During an agent turn, rejected reloads return their error and diagnostics to the harness without a raw player error toast. The agent is instructed to repair, repeat headless testing, and retry reload in that same request. Tool completion clears the running-tool status while the model continues. Manual load failures still show their error to the player; the previous accepted game remains running on rejection.

### Separate agent testing

Pi can run the current workspace in a separate Godot process without replacing or pausing your game. Headless testing is always available. Enable **Allow rendered agent tests** in Settings to permit a separate rendered window. It starts minimized with NO_FOCUS, audio is muted, and screenshots do not restore it or take focus. This permission is checked on each launch and does not change the system instructions.

The tools are `start_test_game`, `read_test_log`, `test_game_action`, and `stop_test_game`. Pi chooses its testing strategy and duration. Actions can inspect game nodes/properties, call game methods, send named input actions, and capture rendered screenshots. Actions return an action ID immediately; poll that ID to retrieve the result. A hung action leaves Pi free to inspect logs or stop the process. One test process runs at a time. Starting a test returns a run ID immediately; reading its log reports startup progress. Tests still use the production loader and script-loading policy.

Stop requests a clean exit, then forces termination after a five-second shutdown grace period if necessary. The result reports the exit code, shutdown method, and reason. The chat Stop button also requests test shutdown when it cancels Pi. Host teardown terminates remaining test processes. A separate watchdog thread detects a missing host heartbeat, requests a clean exit, and escalates after five seconds even if game code hangs. Startup reconciles unfinished runs without blindly killing saved PIDs. There is no automatic test-duration limit.

Each test has separate writable user data and raw engine/stdout/stderr files under `host/games/<game>/tests/<run-id>/`. Shared runtime diagnostics use their own sessions under `tests/runtime/`, with the existing JSONL rotation, retention, and loss reporting. Records identify the test run and mode. Raw stdout/stderr capture is capped at 2 MiB per stream and discarded-byte counts are explicit; engine logs provide additional crash/startup evidence. Omit the run ID from `read_test_log` to list recent runs and the current rendered permission. Completed-run logs remain readable after reopening until retention expires them. Each active run has a 32 MiB evidence budget (including engine logs and user data); exceeding it requests shutdown. The per-game test budget is 64 MiB, with oldest completed runs removed first and explicit retention metadata. These are storage limits, not execution timeouts.

Tests never promote the working snapshot or approve a live reload. Their workspace inputs are not frozen; separate user data is not a filesystem sandbox. A successful test is evidence about that test execution, not a guarantee that a later live reload will succeed.

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

Logs are bounded and redact Authorization, bearer, API-key, token and secret values, including JSON credential fields in provider errors. Ordinary counts such as `tokens=7000` stay readable.

### Legacy transcript migration

A game that has readable pre-Pi dialogue but no Pi session imports that dialogue into the **empty Pi session once**. GameSmith starts/resumes Pi before appending the current player request to `transcript.jsonl`, so that new request cannot be mistaken for legacy history. Once the Pi session has entries, restart/resume does not import the readable transcript again.

The readable transcript remains a product/UI artifact. It is not used to reconstruct an existing Pi provider history.

## Pi-native compaction and prompt-cache friendliness

Pi owns the durable agent session, including assistant reasoning, tool calls/results, checkpoint entries, and compaction.

GameSmith keeps only product-level controls around Pi's native compactor:

- **Auto compact at estimated tokens** defaults to 100,000; 0 disables GameSmith's trigger.
- **Keep recent tokens verbatim** defaults to 20,000 and is written to Pi's `compaction.keepRecentTokens`.
- **Compact now** invokes Pi's native `compact` RPC. Post-compaction token usage may be unknown until the next model response; GameSmith reports it as unknown rather than zero.
- When automatic compaction is enabled, Pi also handles in-turn context pressure and resumes unfinished work after a successful automatic checkpoint. Completed work is not restarted. Failed compaction is reported without replacing history and is not retried again in the same player request.
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
node --test tests/workspace-paths.test.mjs tests/model-capabilities.test.mjs tests/diagnostic-delivery.test.mjs tests/empty-response-retry.test.mjs tests/command-code.test.mjs
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

Verification uses `node tools/testing/verify.mjs --suite full --output summary`. Complete evidence is saved even with compact output; see [verification commands, failure reruns and reuse](tools/testing/README.md).
