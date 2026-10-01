# Plan: Live 50-char LLM message snippets in chat

## Context

Today the in-app chat only shows the agent's **final** message after a turn completes.
`agent_controller.gd:114` (`assistant_message.emit`) only fires when the model returns
content with **no tool calls**. Everything in between is invisible in chat:

- intermediate assistant text sent alongside tool calls (dropped at `agent_controller.gd:94-161`)
- thinking/reasoning blocks (never read anywhere in `src/`)
- tool calls (only written to `gamesmith.log` at `agent_controller.gd:154`)

Goal: post a **live 50-char snippet** to the chat for each of those three kinds while the
agent works. Final full assistant message keeps posting exactly as it does now.

## Decisions (confirmed with user)

| Decision | Answer |
|---|---|
| Snippets persisted to `transcript.jsonl`? | **No** — ephemeral, live view only. Reopen shows user + final assistant as today. |
| Tool-call snippet content | **`name + args`** truncated to 50, e.g. `search_text {"query":"find the playe…` |
| Assistant/thinking snippet content | first 50 chars of the text |
| Trailing `…` when truncated | yes — chat is user-facing (log convention of no-ellipsis stays as-is) |
| Final full assistant message | unchanged — no duplicate snippet for it (the full message supersedes it) |

## Design

### `src/agent/agent_controller.gd`
1. New signal: `signal llm_snippet(kind: String, text: String)` with kinds `"thinking"`, `"assistant"`, `"tool"`.
2. New helper:
   ```gdscript
   func _snippet(value: Variant) -> String:
       if value == null: return ""
       var flat = str(value).replace("\r", " ").replace("\n", " ").strip_edges()
       if flat == "": return ""
       return flat.left(50) + ("…" if flat.length() > 50 else "")
   ```
   `Variant` + null guard is required, not paranoid: OpenAI-compatible endpoints commonly
   return `"content": null` alongside `tool_calls`, and `str(null)` in GDScript is `"<null>"`.
   Newline flattening mirrors `app_logger.gd:43-45` so a snippet is always one chat line.
3. Emit points:
   - After `calls` is read (`agent_controller.gd:94`):
     - thinking: `_snippet(message.get("reasoning_content", message.get("reasoning", "")))` → emit if non-empty.
       (`reasoning_content` = DeepSeek-style, `reasoning` = OpenRouter unified — two keys, one line, covers the ecosystem.)
     - assistant: only when `calls` is non-empty (intermediate) and content non-empty → emit `"assistant"`.
       Final message already posts in full via `assistant_message.emit` — no duplicate snippet.
   - In the tool loop right after `raw_args` (`agent_controller.gd:135`), **before** args parsing/execution:
     `_snippet("%s %s" % [fn_name, raw_args])` → emit `"tool"`.
     Placed before `JSON.parse` so a malformed call is still visible; malformed entries
     that fail the earlier `TYPE_DICTIONARY` guards never reach here (no name to show).
4. Snippets are **not** appended to `conversation` (would pollute provider context) and
   **not** written to `transcript` (ephemeral decision) or `AppLogger` (provider response
   is already logged with `response_excerpt`).

### `src/ui/app.gd`
1. Wire next to the existing hook (`app.gd:233`):
   `agent.llm_snippet.connect(func(kind, text): _append_chat(kind, text))`
2. `_append_chat` role mapping (`app.gd:279-280`) — replace nested ternaries with dict lookups,
   keeping the `HOST`/grey fallback for unknown roles:
   ```gdscript
   var label = {"user": "YOU", "assistant": "AGENT", "thinking": "THINK", "tool": "TOOL"}.get(role, "HOST")
   var color = {"user": "9bb7ff", "assistant": "c2f0cb", "thinking": "6f7ea3", "tool": "e5b978"}.get(role, "8393b2")
   ```
   Snippets append synchronously before `_append_chat`'s `await`, so emit order = chat order.
   No transcript/`_load_transcript` changes — ephemeral by construction.

## TDD (red → green)

### RED — `tests/test_runner.gd`
New test `_test_llm_snippets_reach_chat()`, registered in `run()` (after `_test_enter_sends_chat_message`).

Setup mirrors `_test_library_is_blocked_while_agent_works` (app instance, no chat overlay needed):
- create workspace, instantiate `main.tscn`, `app._open_game(name)`, FakeProvider override
- push response 1 (intermediate): `reasoning_content` > 60 chars, `content` > 60 chars,
  `tool_calls: [_tool_call("s1", "search_text", {"query": "<long query>"})]`
- push response 2 (final): `content: "All done."`
- `app.chat_input.text = "what is going on"` (starts with `what ` → completion guard
  requires no workspace change, so no reload/mutation plumbing needed in this test)
- `app._send_chat()` → poll until `not app.agent.busy`

Assert via `app.transcript_view.get_parsed_text()` (precedent: `http_integration_runner.gd:91`):
1. thinking snippet present: exactly `flattened.left(50) + "…"`
2. intermediate assistant snippet present (this is the text that is invisible today)
3. tool snippet present: `search_text {…`.left(50) + "…"
4. final full message `"All done."` still posted
5. `TranscriptStoreScript.new().read_all(name).size() == 2` → snippets stayed out of the durable transcript

Run full suite → the snippet assertions FAIL (feature missing), nothing else changes. That is the RED.

### GREEN — minimal implementation
Apply the two-file changes above. Run the full suite → everything passes, including the new test.

### REFACTOR
Only the `_append_chat` ternary → dict lookup (needed to make the mapping readable with 4 roles).
No extra behavior, no config, no settings toggle (YAGNI).

## Verification

```powershell
& "C:\GameInGame\GameSmith-Windows\runtime\Godot_v4.7.2-stable_win64.exe" --headless --path C:\GameInGame --script res://tests/test_runner.gd
```
Check `$LASTEXITCODE -eq 0` and the `TESTS: N passed, 0 failed` line.
Existing 25 tests must stay green (esp. `_test_agent_generation_and_second_edit`,
which asserts exact transcript counts — proof we did not leak snippets into stores).

## Files touched
- `src/agent/agent_controller.gd` (signal + helper + 3 emit sites)
- `src/ui/app.gd` (1 connect line + role maps)
- `tests/test_runner.gd` (1 new test + 1 registration line)

## Out of scope (deliberately)
- Streaming responses (provider is one-shot JSON; nothing to stream from)
- Persisting snippets / snippet roles in `transcript.jsonl`
- Escaping BBCode in chat text (pre-existing behavior for full messages, unchanged)
- Log-side snippet formatting (AppLogger already truncates its own fields)
