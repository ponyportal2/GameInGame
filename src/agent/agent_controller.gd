class_name AgentController
extends Node

const ConversationStoreScript = preload("res://src/core/conversation_store.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")

signal status_changed(text: String)
signal assistant_message(text: String)
signal finished(ok: bool)

const DEFAULT_MAX_STEPS = 150
const MIN_AGENT_STEPS = 1
const MAX_AGENT_STEPS = 500
const DEFAULT_LLM_CALL_DELAY_SEC = 6.0
const MIN_LLM_CALL_DELAY_SEC = 0.0
const MAX_LLM_CALL_DELAY_SEC = 300.0
const MAX_CONSECUTIVE_VERIFICATION_REJECTIONS = 3

static var _last_provider_call_finished_msec: Dictionary = {}
var game_name = ""
var tools: GameTools
var metadata = MetadataStore.new()
var transcript = TranscriptStore.new()
var conversation = ConversationStoreScript.new()
var busy = false
var session_id = ""
# Narrow injection seam used by deterministic integration tests. Production leaves this null.
var provider_override: Variant = null

func configure(p_game_name: String, p_tools: GameTools) -> void:
    game_name = p_game_name
    tools = p_tools
    session_id = "%s-%d" % [game_name.md5_text().left(8), Time.get_unix_time_from_system()]
    AppLoggerScript.game_event(game_name, "agent.session", "session=%s configured" % session_id)

func send_player_request(text: String) -> void:
    if busy: return
    busy = true
    var had_conversation = conversation.exists(game_name)
    var prior_history: Array = conversation.read_for_provider(game_name)
    if prior_history.is_empty() and not had_conversation:
        prior_history = conversation.import_legacy_transcript(game_name, transcript.read_all(game_name, 1000000))
    if conversation.needs_recovery_marker(prior_history):
        var recovery = conversation.recovery_marker()
        conversation.append(game_name, recovery)
        prior_history.append(recovery)
        AppLoggerScript.game_event(game_name, "conversation.recovery", "session=%s closed an unfinished prior turn before the new request" % session_id, "WARN")
    var user_message = {"role": "user", "content": text}
    transcript.append(game_name, "user", text)
    conversation.append(game_name, user_message)
    status_changed.emit("Thinking and editing…")
    var settings = metadata.global_settings()
    var game_meta = metadata.read_game(game_name)
    var provider_id = str(game_meta.get("provider_override", ""))
    var model = str(game_meta.get("model_override", ""))
    if provider_id == "": provider_id = str(settings.get("provider", "openrouter"))
    if model == "": model = str(settings.get("model", ProviderFactory.defaults().get(provider_id, "")))
    var provider = provider_override if provider_override != null else ProviderFactory.make(self, provider_id, model, metadata.credentials(), session_id, settings)
    if provider == null:
        _fail(ProviderFactory.unavailable_reason(provider_id))
        return

    var messages: Array = [{"role": "system", "content": _system_prompt()}]
    messages.append_array(prior_history)
    messages.append(user_message)
    var max_steps = clampi(int(settings.get("max_agent_steps", DEFAULT_MAX_STEPS)), MIN_AGENT_STEPS, MAX_AGENT_STEPS)
    var llm_call_delay_sec = clampf(float(settings.get("llm_call_delay_sec", DEFAULT_LLM_CALL_DELAY_SEC)), MIN_LLM_CALL_DELAY_SEC, MAX_LLM_CALL_DELAY_SEC)
    var throttle_key = "%s|%s" % [provider_id, model]
    AppLoggerScript.game_event(game_name, "agent.request", "session=%s provider=%s model=%s max_steps=%d llm_delay_sec=%.1f prior_messages=%d request=%s" % [session_id, provider_id, model, max_steps, llm_call_delay_sec, prior_history.size(), text.left(500)])
    var started_without_main = not FileAccess.file_exists(tools.workspace.path_join("main.gd"))
    var request_requires_change = _request_requires_workspace_change(text)
    var turn_had_workspace_mutation = false
    var pending_code_changes = false
    var had_successful_reload = false
    var consecutive_verification_rejections = 0
    var tool_schema = _tool_schema()
    for step in max_steps:
        status_changed.emit("Agent step %d/%d…" % [step + 1, max_steps])
        await _wait_for_provider_slot(llm_call_delay_sec, throttle_key, step + 1)
        var provider_summary = ""
        if provider.has_method("diagnostic_summary"):
            provider_summary = str(provider.diagnostic_summary(messages, tool_schema))
        AppLoggerScript.game_event(game_name, "provider.request", "session=%s step=%d %s" % [session_id, step + 1, provider_summary])
        var result: Dictionary = await provider.complete(messages, tool_schema)
        _last_provider_call_finished_msec[throttle_key] = Time.get_ticks_msec()
        var diagnostics = result.get("diagnostics", {})
        AppLoggerScript.game_event(game_name, "provider.response", "session=%s step=%d ok=%s diagnostics=%s" % [session_id, step + 1, str(result.get("ok", false)), JSON.stringify(diagnostics)], "INFO" if bool(result.get("ok", false)) else "ERROR")
        if not result.ok:
            AppLoggerScript.game_event(game_name, "provider.error", "session=%s step=%d error=%s" % [session_id, step + 1, str(result.error)], "ERROR")
            _fail(str(result.error))
            return
        var message: Dictionary = result.message.duplicate(true)
        messages.append(message)
        var calls: Array = message.get("tool_calls", [])
        if calls.is_empty():
            var content = str(message.get("content", "Done."))
            if content.strip_edges() == "": content = "Done."
            var guard_reason = _completion_guard(started_without_main, request_requires_change, turn_had_workspace_mutation, pending_code_changes, had_successful_reload)
            if guard_reason != "":
                consecutive_verification_rejections += 1
                AppLoggerScript.game_event(game_name, "agent.verification", "session=%s step=%d rejected=%s content=%s" % [session_id, step + 1, guard_reason, content.left(500)], "WARN")
                if consecutive_verification_rejections >= MAX_CONSECUTIVE_VERIFICATION_REJECTIONS:
                    _fail("The model repeatedly finished without completing the requested game change (%d attempts). No further provider calls were made. Try the request again or use a different model/provider." % MAX_CONSECUTIVE_VERIFICATION_REJECTIONS)
                    return
                var correction = {
                    "role": "user",
                    "content": "[GameSmith verifier] Your previous response did not complete the request: %s Continue the same request with tool calls now. Do not send another progress-only or completion message until the condition is actually satisfied." % guard_reason
                }
                messages.append(correction)
                continue
            message["content"] = content
            conversation.append(game_name, message)
            transcript.append(game_name, "assistant", content)
            assistant_message.emit(content)
            AppLoggerScript.game_event(game_name, "agent.finished", "session=%s step=%d ok=true" % [session_id, step + 1])
            status_changed.emit("Ready")
            busy = false
            finished.emit(true)
            return
        consecutive_verification_rejections = 0
        conversation.append(game_name, message)
        for call in calls:
            if typeof(call) != TYPE_DICTIONARY:
                var malformed_message = {"role": "tool", "tool_call_id": "", "content": JSON.stringify({"ok": false, "error": "Malformed tool call: expected an object."})}
                messages.append(malformed_message)
                conversation.append(game_name, malformed_message)
                continue
            var fn = call.get("function", {})
            if typeof(fn) != TYPE_DICTIONARY:
                var missing_function_message = {"role": "tool", "tool_call_id": str(call.get("id", "")), "content": JSON.stringify({"ok": false, "error": "Malformed tool call: missing function object."})}
                messages.append(missing_function_message)
                conversation.append(game_name, missing_function_message)
                continue
            var fn_name = str(fn.get("name", ""))
            var raw_args = str(fn.get("arguments", "{}"))
            var json = JSON.new()
            var parse_error = json.parse(raw_args)
            var parsed = json.data if parse_error == OK else null
            var tool_result: Dictionary
            if parse_error != OK or typeof(parsed) != TYPE_DICTIONARY:
                tool_result = {"ok": false, "error": "Malformed tool arguments: expected a JSON object."}
            else:
                status_changed.emit("Running %s…" % fn_name)
                tool_result = tools.execute(fn_name, parsed)
                if bool(tool_result.get("ok", false)):
                    if _is_workspace_mutation(fn_name):
                        turn_had_workspace_mutation = true
                    if _is_code_mutation(fn_name, parsed):
                        pending_code_changes = true
                    if fn_name == "reload_game":
                        had_successful_reload = true
                        pending_code_changes = false
            var tool_error = str(tool_result.get("error", tool_result.get("output", ""))).left(500)
            AppLoggerScript.game_event(game_name, "agent.tool", "session=%s step=%d name=%s ok=%s error=%s" % [session_id, step + 1, fn_name, str(tool_result.get("ok", false)), tool_error], "INFO" if bool(tool_result.get("ok", false)) else "WARN")
            var tool_message = {
                "role": "tool",
                "tool_call_id": str(call.get("id", "")),
                "content": JSON.stringify(tool_result)
            }
            messages.append(tool_message)
            conversation.append(game_name, tool_message)
    _fail("The agent reached the per-request step limit (%d). Your files were left as-is; continue with another message if needed." % max_steps)


func _wait_for_provider_slot(delay_sec: float, throttle_key: String, step_number: int) -> void:
    if delay_sec <= 0.0:
        return
    var last_finished = int(_last_provider_call_finished_msec.get(throttle_key, 0))
    if last_finished <= 0:
        return
    var elapsed_sec = float(Time.get_ticks_msec() - last_finished) / 1000.0
    var remaining = delay_sec - elapsed_sec
    if remaining <= 0.0:
        return
    status_changed.emit("Waiting %.1fs for provider rate limit…" % remaining)
    AppLoggerScript.game_event(game_name, "provider.delay", "session=%s step=%d wait_sec=%.3f" % [session_id, step_number, remaining])
    await get_tree().create_timer(remaining, true).timeout

func _completion_guard(started_without_main: bool, request_requires_change: bool, turn_had_workspace_mutation: bool, pending_code_changes: bool, had_successful_reload: bool) -> String:
    if started_without_main and request_requires_change and (not FileAccess.file_exists(tools.workspace.path_join("main.gd")) or not had_successful_reload):
        return "This game started without a playable main.gd, and no generated game has been successfully reloaded yet."
    if pending_code_changes:
        return "GDScript changes were made after the last successful reload. Call reload_game and resolve any load error before finishing."
    if request_requires_change and not turn_had_workspace_mutation:
        return "The player requested a game change, but this turn made no workspace changes."
    return ""

func _is_workspace_mutation(tool_name: String) -> bool:
    return tool_name in ["write_file", "patch_file", "move_path", "delete_path"]

func _is_code_mutation(tool_name: String, args: Dictionary) -> bool:
    if tool_name in ["delete_path", "move_path"]:
        return true
    if not tool_name in ["write_file", "patch_file"]:
        return false
    var path = str(args.get("path", "")).to_lower()
    return path.ends_with(".gd") or path.ends_with(".gdshader")

func _request_requires_workspace_change(text: String) -> bool:
    var lower = text.strip_edges().to_lower()
    for prefix in ["what ", "why ", "where ", "when ", "who ", "which ", "how ", "explain ", "tell me ", "describe ", "list ", "show me ", "is ", "are ", "does ", "do "]:
        if lower.begins_with(prefix):
            return false
    for marker in ["create", "build", "make", "add", "change", "update", "modify", "fix", "remove", "delete", "rename", "replace", "increase", "decrease", "faster", "slower", "speed up", "slow down", "implement", "rework", "recolor", "resize", "spawn"]:
        if marker in lower:
            return true
    return false

func _fail(message: String) -> void:
    AppLoggerScript.game_event(game_name, "agent.failed", "session=%s error=%s" % [session_id, message], "ERROR")
    conversation.append(game_name, {"role": "assistant", "content": "GameSmith stopped this turn with an error: " + message})
    transcript.append(game_name, "assistant", "Error: " + message)
    assistant_message.emit("Error: " + message)
    status_changed.emit("Ready")
    busy = false
    finished.emit(false)

func _system_prompt() -> String:
    return """You are the game-building agent inside GameSmith Host. The player expects you to act, not merely explain.

Rules:
- Work ONLY through the structured tools provided. There is no shell tool.
- The current workspace is the entire generated game. Never ask for or reference host files, credentials, or other games.
- You receive durable prior player/assistant conversation after GameSmith restarts. Completed historical tool-call/result chatter may be compacted to keep context efficient; the full raw trace stays on disk for debugging. Treat the workspace and Git as the technical source of truth if old conversation details and current files ever differ.
- Before changing an existing game, inspect the relevant current files unless their exact current contents are already present in recent tool results. Do not guess file contents from conversation alone.
- v1 generated games are GDScript-only. main.gd at workspace root is the entry point and must extend a Node type.
- Build the scene tree from code. Do not create .tscn files or depend on imported images, models, sounds, or fonts.
- 2D and 3D are both allowed. Prefer engine primitives, procedural geometry, built-in drawing, and text-created shaders/materials.
- Keep code small, readable, and robust. Multiple .gd files are supported. For sibling scripts, resolve from get_script().resource_path.get_base_dir() so renamed games remain portable.
- Make requested changes immediately unless the request is materially ambiguous.
- File writes never reload automatically. Call reload_game only when the edit set is ready to try.
- A failed reload does not automatically retry. Inspect files/logs and choose whether to fix/reload in the same player request.
- Use Git when a coherent milestone is worth saving; do not commit every tiny write.
- The game is paused while chat is open and starts fresh after a successful reload.
- Avoid dangerous global engine mutations. Do not quit the host tree, change the host window mode, or write outside the workspace.
- For input, create InputEventKey/Mouse checks directly in _input/_unhandled_input rather than modifying ProjectSettings input maps.
- For a request that changes the game, start with tool calls. Do not send progress-only text before inspecting/editing with tools.
- A plain-text claim such as "Done" is not proof of completion. GameSmith verifies that new games were actually created/reloaded and that code edits were reloaded. If verification rejects a completion, continue using tools.
- Finish with a concise player-facing summary after tool work.
"""

func _tool_schema() -> Array:
    return [
        _tool("list_files", "List files recursively within the current game workspace.", {"path": _str("Optional relative directory")}, []),
        _tool("read_file", "Read a UTF-8 text file in the current game workspace.", {"path": _str("Relative path")}, ["path"]),
        _tool("search_text", "Search readable workspace files for text.", {"query": _str("Text to find")}, ["query"]),
        _tool("write_file", "Create or fully replace a UTF-8 text file.", {"path": _str("Relative path"), "content": _str("Complete file content")}, ["path", "content"]),
        _tool("patch_file", "Replace one exact unique text fragment in a file.", {"path": _str("Relative path"), "old_text": _str("Exact unique old text"), "new_text": _str("Replacement text")}, ["path", "old_text", "new_text"]),
        _tool("move_path", "Move or rename a file/directory within the workspace.", {"from": _str("Existing relative path"), "to": _str("Destination relative path")}, ["from", "to"]),
        _tool("delete_path", "Delete a file or directory within the workspace.", {"path": _str("Relative path")}, ["path"]),
        _tool("git_status", "Show Git branch and working tree status.", {}, []),
        _tool("git_diff", "Show the current unstaged Git diff.", {}, []),
        _tool("git_log", "Show recent Git commits.", {"limit": {"type": "integer", "minimum": 1, "maximum": 50}}, []),
        _tool("git_commit", "Stage all workspace changes and create a Git commit.", {"message": _str("Commit message")}, ["message"]),
        _tool("reload_game", "Compile/instantiate main.gd and replace the active generated game only if the candidate can be created.", {}, []),
        _tool("read_runtime_log", "Read bounded host load/runtime log and recent Godot log tail.", {}, [])
    ]

func _tool(name: String, description: String, props: Dictionary, required: Array) -> Dictionary:
    return {"type": "function", "function": {"name": name, "description": description, "parameters": {"type": "object", "properties": props, "required": required, "additionalProperties": false}}}

func _str(description: String) -> Dictionary:
    return {"type": "string", "description": description}
