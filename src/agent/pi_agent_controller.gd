class_name PiAgentController
extends Node

signal status_changed(text: String)
signal assistant_message(text: String)
signal llm_snippet(kind: String, text: String)
signal llm_stream_delta(kind: String, text: String)
signal llm_stream_end(kind: String)
signal finished(ok: bool)
signal reload_approval_changed(pending: bool)

const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const PiRuntimeConfigScript = preload("res://src/pi/pi_runtime_config.gd")
const PiRpcSessionScript = preload("res://src/pi/pi_rpc_session.gd")

const DEFAULT_MAX_STEPS = 150
const MIN_AGENT_STEPS = 1
const MAX_AGENT_STEPS = 500
const DEFAULT_LLM_CALL_DELAY_SEC = 6.0
const MIN_LLM_CALL_DELAY_SEC = 0.0
const MAX_LLM_CALL_DELAY_SEC = 300.0

var game_name := ""
var tools
var metadata = MetadataStoreScript.new()
var transcript = TranscriptStoreScript.new()
var rpc
var runtime_config: Dictionary = {}
var busy := false
var last_context_tokens := 0
var last_error := ""
var pending_provider_error := ""
var turn_count := 0
var limit_abort_sent := false
var streamed_text := false
var current_streamed_text := false
var current_streamed_thinking := false
var bridge_dir := ""
var restart_after_finish := false
var operation_id := 0
var pending_reload: Dictionary = {}
var pending_test_commands: Array[Dictionary] = []
var auto_compaction_failed_operation := -1

func configure(p_game_name: String, p_tools) -> void:
    game_name = p_game_name
    tools = p_tools
    process_mode = Node.PROCESS_MODE_ALWAYS

func send_player_request(text: String) -> void:
    if busy:
        return
    busy = true
    operation_id += 1
    var operation = operation_id
    last_error = ""
    pending_provider_error = ""
    turn_count = 0
    limit_abort_sent = false
    streamed_text = false
    if has_meta("_pi_settled"):
        remove_meta("_pi_settled")
    AppLoggerScript.game_event(game_name, "pi.request", "request=%s" % text.left(500))
    status_changed.emit("Starting Pi…")

    # Start/resume Pi before writing the current request to the human transcript.
    # On a brand-new session, Pi may import pre-existing readable dialogue once;
    # the current request must not be mistaken for legacy history.
    var ready = await _ensure_runtime()
    if operation != operation_id:
        return
    transcript.append(game_name, "user", text)
    if not bool(ready.get("ok", false)):
        _fail(str(ready.get("error", "Pi is unavailable.")))
        return

    await _maybe_auto_compact("before_request")
    if operation != operation_id:
        return
    if auto_compaction_failed_operation == operation:
        _fail("Could not compact the conversation before this request. History and edits were kept. Retry Compact now before continuing.")
        return
    status_changed.emit("Pi is working…")
    var accepted: Dictionary = await rpc.command({"type": "prompt", "message": text})
    if operation != operation_id:
        return
    if not bool(accepted.get("success", false)):
        _fail("Pi rejected the prompt: " + str(accepted.get("error", "unknown error")))
        return

    while operation == operation_id and busy and rpc != null and rpc.running:
        if bool(get_meta("_pi_settled", false)):
            remove_meta("_pi_settled")
            break
        await get_tree().process_frame

    if operation != operation_id:
        return
    if rpc == null or not rpc.running:
        _fail(last_error if last_error != "" else "Pi process stopped unexpectedly.")
        return
    if last_error != "":
        _fail(last_error)
        return

    var last: Dictionary = await rpc.command({"type": "get_last_assistant_text"})
    if operation != operation_id:
        return
    var final_text = ""
    if bool(last.get("success", false)):
        final_text = str(last.get("data", {}).get("text", "")).strip_edges()
    if final_text != "":
        transcript.append(game_name, "assistant", final_text)
        if not streamed_text:
            assistant_message.emit(final_text)
    await _refresh_context_usage()
    if operation != operation_id:
        return
    await _maybe_auto_compact("after_turn")
    if operation != operation_id:
        return
    status_changed.emit("Ready")
    busy = false
    if restart_after_finish:
        restart_after_finish = false
        restart_runtime()
    finished.emit(true)

func compact_now() -> Dictionary:
    if busy:
        return {"ok": false, "error": "Agent is busy."}
    busy = true
    operation_id += 1
    var operation = operation_id
    var ready = await _ensure_runtime()
    if operation != operation_id:
        return {"ok": false, "cancelled": true, "error": "Compaction cancelled."}
    if not bool(ready.get("ok", false)):
        busy = false
        return ready
    status_changed.emit("Compacting Pi session…")
    var response: Dictionary = await rpc.command({"type": "compact"})
    if operation != operation_id:
        return {"ok": false, "cancelled": true, "error": "Compaction cancelled."}
    if not bool(response.get("success", false)):
        busy = false
        status_changed.emit("Ready")
        var error = str(response.get("error", "Pi compaction failed."))
        var lower = error.to_lower()
        var no_op = _compaction_is_noop(lower)
        return {"ok": false, "no_op": no_op, "error": error}
    var data: Dictionary = response.get("data", {})
    var usage_known = await _refresh_context_usage()
    if operation != operation_id:
        return {"ok": false, "cancelled": true, "error": "Compaction cancelled."}
    busy = false
    status_changed.emit("Ready")
    return {
        "ok": true,
        "summary": str(data.get("summary", "")),
        "tokens_before": int(data.get("tokensBefore", 0)),
        "tokens_after": last_context_tokens if usage_known else null
    }

func cancel() -> void:
    if not busy:
        return
    operation_id += 1
    restart_after_finish = false
    AppLoggerScript.game_event(game_name, "pi.cancel", "Cancelled by the player; existing file edits are kept.")
    restart_runtime()
    busy = false
    last_error = ""
    pending_provider_error = ""
    llm_stream_end.emit("assistant")
    llm_stream_end.emit("thinking")
    assistant_message.emit("Cancelled. File edits already made were kept.")
    status_changed.emit("Ready")
    finished.emit(false)

func restart_runtime() -> void:
    _clear_pending_reload()
    pending_test_commands.clear()
    if tools != null and is_instance_valid(tools.test_supervisor):
        tools.test_supervisor.stop_all()
    if rpc != null:
        rpc.retire()
    rpc = null
    runtime_config = {}
    bridge_dir = ""
    last_context_tokens = 0

func settings_changed() -> void:
    if busy:
        restart_after_finish = true
    else:
        restart_runtime()

func context_tokens() -> int:
    return last_context_tokens

func _exit_tree() -> void:
    restart_runtime()

func _process(_delta: float) -> void:
    _service_host_bridge()

func _ensure_runtime() -> Dictionary:
    if rpc != null and rpc.running:
        return {"ok": true}
    var settings = metadata.global_settings()
    var game_meta = metadata.read_game(game_name)
    runtime_config = PiRuntimeConfigScript.prepare(game_name, tools.workspace, settings, metadata.credentials(), game_meta)
    if not bool(runtime_config.get("ok", false)):
        return runtime_config
    runtime_config["game_name"] = game_name
    bridge_dir = str(runtime_config.bridge_dir)
    rpc = PiRpcSessionScript.new()
    add_child(rpc)
    rpc.record_received.connect(_on_pi_record)
    rpc.stderr_line.connect(_on_pi_stderr)
    rpc.process_stopped.connect(func(message):
        last_error = message
        AppLoggerScript.game_event(game_name, "pi.process_stopped", message, "ERROR")
    )
    var started: Dictionary = rpc.start(runtime_config)
    if not bool(started.get("ok", false)):
        rpc.queue_free()
        rpc = null
        return started
    AppLoggerScript.game_event(game_name, "pi.started", "pid=%d model=%s session_dir=%s" % [int(started.get("pid", -1)), str(runtime_config.model), str(runtime_config.session_dir)])

    var session = rpc
    var synced = await _sync_runtime_state(session)
    if session != rpc:
        return {"ok": false, "error": "Pi runtime was cancelled or replaced."}
    if not bool(synced.get("ok", false)):
        return synced
    var auto_policy: Dictionary = await rpc.command({"type": "set_auto_compaction", "enabled": int(settings.get("compaction_auto_tokens", 100000)) > 0})
    if not bool(auto_policy.get("success", false)):
        return {"ok": false, "error": "Could not configure Pi compaction policy: " + str(auto_policy.get("error", ""))}
    await _refresh_context_usage()
    return {"ok": true}

func _sync_runtime_state(session) -> Dictionary:
    var state: Dictionary = await session.command({"type": "get_state"})
    if not bool(state.get("success", false)):
        return {"ok": false, "error": "Could not read Pi session state: " + str(state.get("error", ""))}
    var data: Dictionary = state.get("data", {})
    var current_model = data.get("model", {})
    var current_provider = str(current_model.get("provider", "")) if typeof(current_model) == TYPE_DICTIONARY else ""
    var current_model_id = str(current_model.get("id", "")) if typeof(current_model) == TYPE_DICTIONARY else ""
    if current_provider != str(runtime_config.provider) or current_model_id != str(runtime_config.model):
        var changed: Dictionary = await session.command({
            "type": "set_model",
            "provider": str(runtime_config.provider),
            "modelId": str(runtime_config.model)
        })
        if not bool(changed.get("success", false)):
            return {"ok": false, "error": "Could not select Pi model %s/%s: %s" % [str(runtime_config.provider), str(runtime_config.model), str(changed.get("error", ""))]}
        data["model"] = changed.get("data", {})
    var selected_model = data.get("model", {})
    runtime_config["context_window"] = int(selected_model.get("contextWindow", 0))
    runtime_config["max_tokens"] = int(selected_model.get("maxTokens", 0))
    var desired_thinking = str(runtime_config.get("thinking", "medium"))
    if not bool(selected_model.get("reasoning", false)):
        desired_thinking = "off"
    if desired_thinking == "":
        desired_thinking = "medium"
    if str(data.get("thinkingLevel", "")) != desired_thinking:
        var thinking_result: Dictionary = await session.command({"type": "set_thinking_level", "level": desired_thinking})
        if not bool(thinking_result.get("success", false)):
            return {"ok": false, "error": "Could not set Pi thinking level %s: %s" % [desired_thinking, str(thinking_result.get("error", ""))]}
    var wanted_name = str(runtime_config.get("game_name", ""))
    var current_name = str(data.get("sessionName", ""))
    if wanted_name != "" and current_name != wanted_name:
        var name_result: Dictionary = await session.command({"type": "set_session_name", "name": wanted_name})
        if not bool(name_result.get("success", false)):
            return {"ok": false, "error": "Could not name Pi session: " + str(name_result.get("error", ""))}
    return {"ok": true}

func _refresh_context_usage() -> bool:
    if rpc == null or not rpc.running:
        return false
    var session = rpc
    var stats: Dictionary = await session.command({"type": "get_session_stats"})
    if session != rpc or rpc == null or not rpc.running or not bool(stats.get("success", false)):
        return false
    var usage = stats.get("data", {}).get("contextUsage", null)
    if typeof(usage) == TYPE_DICTIONARY and usage.get("tokens") != null:
        last_context_tokens = int(usage.tokens)
        return true
    return false

func _compaction_is_noop(message: String) -> bool:
    var lower = message.to_lower()
    return "nothing to compact" in lower or "session too small" in lower

func _maybe_auto_compact(phase: String) -> void:
    if auto_compaction_failed_operation == operation_id:
        return
    var session = rpc
    var threshold = maxi(0, int(metadata.global_settings().get("compaction_auto_tokens", 100000)))
    if threshold <= 0:
        return
    var usage_known = await _refresh_context_usage()
    if not usage_known or session != rpc or rpc == null or not rpc.running:
        return
    var context_window = int(runtime_config.get("context_window", 0))
    if context_window > 0:
        threshold = mini(threshold, maxi(1, int(context_window * 0.75) - int(runtime_config.get("max_tokens", 0))))
    if last_context_tokens <= 0 or last_context_tokens < threshold:
        return
    status_changed.emit("Auto-compacting Pi session…")
    AppLoggerScript.game_event(game_name, "pi.compaction.auto", "phase=%s context_tokens=%d threshold=%d" % [phase, last_context_tokens, threshold])
    var response: Dictionary = await session.command({"type": "compact"})
    if session != rpc or rpc == null or not rpc.running:
        return
    if bool(response.get("success", false)):
        await _refresh_context_usage()
    else:
        var error = str(response.get("error", "unknown"))
        if _compaction_is_noop(error):
            return
        auto_compaction_failed_operation = operation_id
        AppLoggerScript.game_event(game_name, "pi.compaction.error", error, "WARN")
        var message = "Automatic compaction failed: " + error + ". Conversation history was kept."
        transcript.append(game_name, "system", message)
        assistant_message.emit(message)

func _on_pi_record(record: Dictionary) -> void:
    var type = str(record.get("type", ""))
    match type:
        "message_start":
            var started_message: Dictionary = record.get("message", {})
            if str(started_message.get("role", "")) == "assistant":
                current_streamed_text = false
                current_streamed_thinking = false
        "message_update":
            var event: Dictionary = record.get("assistantMessageEvent", {})
            var event_type = str(event.get("type", ""))
            if event_type == "text_delta":
                var delta = str(event.get("delta", ""))
                if delta != "":
                    streamed_text = true
                    current_streamed_text = true
                    llm_stream_delta.emit("assistant", delta)
            elif event_type == "text_end":
                llm_stream_end.emit("assistant")
            elif event_type == "thinking_delta":
                var thinking = str(event.get("delta", ""))
                if thinking != "":
                    current_streamed_thinking = true
                    llm_stream_delta.emit("thinking", thinking)
            elif event_type == "thinking_end":
                llm_stream_end.emit("thinking")
        "tool_execution_start":
            var name = str(record.get("toolName", "tool"))
            var args = JSON.stringify(record.get("args", {}))
            llm_snippet.emit("tool", _snippet("%s %s" % [name, args]))
            status_changed.emit("Running %s…" % name)
        "tool_execution_end":
            AppLoggerScript.game_event(game_name, "pi.tool", "name=%s error=%s" % [str(record.get("toolName", "")), str(record.get("isError", false))], "WARN" if bool(record.get("isError", false)) else "INFO")
        "turn_start":
            turn_count += 1
            var limit = clampi(int(metadata.global_settings().get("max_agent_steps", DEFAULT_MAX_STEPS)), MIN_AGENT_STEPS, MAX_AGENT_STEPS)
            if turn_count > limit and not limit_abort_sent:
                limit_abort_sent = true
                last_error = "Pi reached the GameSmith per-request turn limit (%d)." % limit
                rpc.command({"type": "abort"})
        "message_end":
            var message: Dictionary = record.get("message", {})
            if str(message.get("role", "")) == "assistant":
                var content = message.get("content", [])
                if typeof(content) == TYPE_ARRAY:
                    if not current_streamed_text:
                        for block in content:
                            if typeof(block) == TYPE_DICTIONARY and str(block.get("type", "")) == "text":
                                var text = str(block.get("text", ""))
                                if text != "":
                                    streamed_text = true
                                    llm_stream_delta.emit("assistant", text)
                                    llm_stream_end.emit("assistant")
                    if not current_streamed_thinking:
                        for block in content:
                            if typeof(block) == TYPE_DICTIONARY and str(block.get("type", "")) == "thinking":
                                var thinking = str(block.get("thinking", ""))
                                if thinking != "":
                                    llm_stream_delta.emit("thinking", thinking)
                                    llm_stream_end.emit("thinking")
                if str(message.get("stopReason", "")) == "error":
                    pending_provider_error = str(message.get("errorMessage", "Pi provider request failed."))
                else:
                    pending_provider_error = ""
        "auto_retry_start":
            status_changed.emit("Pi retry %d/%d…" % [int(record.get("attempt", 1)), int(record.get("maxAttempts", 3))])
            AppLoggerScript.game_event(game_name, "pi.retry", JSON.stringify(record), "WARN")
        "auto_retry_end":
            if bool(record.get("success", false)):
                pending_provider_error = ""
            else:
                last_error = str(record.get("finalError", pending_provider_error if pending_provider_error != "" else "Pi provider request failed after retries."))
        "compaction_start":
            status_changed.emit("Pi is compacting context…")
            AppLoggerScript.game_event(game_name, "pi.compaction.start", JSON.stringify(record))
        "compaction_end":
            if record.get("reason", "manual") != "manual" and not record.get("result") and record.get("errorMessage") and not record.get("aborted", false) and not _compaction_is_noop(str(record.errorMessage)):
                auto_compaction_failed_operation = operation_id
                var notice = "Automatic compaction failed: " + str(record.errorMessage) + ". Conversation history was kept."
                transcript.append(game_name, "system", notice)
                assistant_message.emit(notice)
            AppLoggerScript.game_event(game_name, "pi.compaction.end", JSON.stringify(record))
        "agent_settled":
            # An abort can settle after its request has already failed. Ignore that
            # late event until the current request has actually entered a Pi turn.
            if busy and turn_count > 0:
                if last_error == "" and pending_provider_error != "":
                    last_error = pending_provider_error
                set_meta("_pi_settled", true)
        _:
            pass

func _on_pi_stderr(text: String) -> void:
    AppLoggerScript.game_event(game_name, "pi.stderr", text, "WARN")

func _service_host_bridge() -> void:
    if bridge_dir == "":
        return
    _service_pending_test_commands()
    var dir = DirAccess.open(bridge_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    var item = dir.get_next()
    var requests: Array[String] = []
    while item != "":
        if not dir.current_is_dir() and item.begins_with("request-") and item.ends_with(".json"):
            requests.append(item)
        item = dir.get_next()
    dir.list_dir_end()
    for file_name in requests:
        var path = bridge_dir.path_join(file_name)
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
        DirAccess.remove_absolute(path)
        if typeof(parsed) != TYPE_DICTIONARY:
            continue
        var request: Dictionary = parsed
        var command = str(request.get("command", ""))
        var result: Dictionary
        if command == "reload_game":
            if pending_reload.is_empty():
                pending_reload = {"request": request, "bridge_dir": bridge_dir, "operation_id": operation_id}
                status_changed.emit("Waiting for reload approval")
                reload_approval_changed.emit(true)
                continue
            result = {"ok": false, "error": "Another reload is already waiting for player approval."}
        elif command == "read_runtime_log":
            result = tools.execute(command, request.get("args", {}))
        elif command in ["start_test_game", "read_test_log", "stop_test_game", "test_game_action"]:
            result = tools.execute(command, request.get("args", {}))
            if result.get("ok", false) and command == "stop_test_game" and result.get("state", "") != "exited":
                pending_test_commands.append({"request": request, "run_id": request.get("args", {}).get("run_id", ""), "command": command, "bridge_dir": bridge_dir, "operation_id": operation_id})
                continue
        elif command == "diagnostic_notice":
            result = tools.runner.runtime_log.prepare_notification() if tools != null and tools.runner != null else {"ok": true, "notice": ""}
        elif command == "compaction_status":
            result = {"ok": true, "blocked": auto_compaction_failed_operation == operation_id}
        elif command == "diagnostic_delivery":
            tools.runner.runtime_log.commit_delivery(str(request.get("args", {}).get("delivery_id", "")))
            result = {"ok": true}
        else:
            result = {"ok": false, "error": "Unknown GameSmith host bridge command: " + command}
        _write_host_response(bridge_dir, request, result)

func _service_pending_test_commands() -> void:
    for pending in pending_test_commands.duplicate():
        if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir:
            pending_test_commands.erase(pending)
            continue
        var state: Dictionary = tools.tests().status(pending.run_id)
        var result: Dictionary = {}
        if pending.command == "stop_test_game" and state.get("state") == "exited":
            result = state
        if not result.is_empty():
            pending_test_commands.erase(pending)
            _write_host_response(bridge_dir, pending.request, result)

func approve_reload() -> void:
    if pending_reload.is_empty():
        return
    var pending = pending_reload
    _clear_pending_reload()
    if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir or bridge_dir == "":
        return
    status_changed.emit("Reloading game...")
    var result: Dictionary = tools.execute("reload_game", pending.request.get("args", {}))
    _write_host_response(bridge_dir, pending.request, result)
    status_changed.emit("Pi is working...")

func _clear_pending_reload() -> void:
    if not pending_reload.is_empty():
        pending_reload = {}
        reload_approval_changed.emit(false)

func _write_host_response(directory: String, request: Dictionary, result: Dictionary) -> void:
    var response_path = directory.path_join("response-%s.json" % str(request.get("id", "")))
    var tmp = response_path + ".tmp"
    var out = FileAccess.open(tmp, FileAccess.WRITE)
    if out != null:
        out.store_string(JSON.stringify(result))
        out.close()
        DirAccess.rename_absolute(tmp, response_path)

func _fail(message: String) -> void:
    _clear_pending_reload()
    AppLoggerScript.game_event(game_name, "pi.failed", message, "ERROR")
    transcript.append(game_name, "assistant", "Error: " + message)
    assistant_message.emit("Error: " + message)
    status_changed.emit("Ready")
    busy = false
    if restart_after_finish:
        restart_after_finish = false
        restart_runtime()
    finished.emit(false)

func _snippet(text: String) -> String:
    var flat = text.replace("\r", " ").replace("\n", " ").strip_edges()
    if flat.length() <= 80:
        return flat
    return flat.left(80) + "…"
