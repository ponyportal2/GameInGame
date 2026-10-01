class_name PiAgentController
extends Node

signal status_changed(text: String)
signal assistant_message(text: String)
signal llm_snippet(kind: String, text: String)
signal llm_stream_delta(kind: String, text: String)
signal llm_stream_end(kind: String)
signal finished(ok: bool)

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
var turn_count := 0
var limit_abort_sent := false
var streamed_text := false
var bridge_dir := ""

func configure(p_game_name: String, p_tools) -> void:
    game_name = p_game_name
    tools = p_tools
    process_mode = Node.PROCESS_MODE_ALWAYS

func send_player_request(text: String) -> void:
    if busy:
        return
    busy = true
    last_error = ""
    turn_count = 0
    limit_abort_sent = false
    streamed_text = false
    transcript.append(game_name, "user", text)
    AppLoggerScript.game_event(game_name, "pi.request", "request=%s" % text.left(500))
    status_changed.emit("Starting Pi…")

    var ready = await _ensure_runtime()
    if not bool(ready.get("ok", false)):
        _fail(str(ready.get("error", "Pi is unavailable.")))
        return

    await _maybe_auto_compact("before_request")
    status_changed.emit("Pi is working…")
    var accepted: Dictionary = await rpc.command({"type": "prompt", "message": text}, 30.0)
    if not bool(accepted.get("success", false)):
        _fail("Pi rejected the prompt: " + str(accepted.get("error", "unknown error")))
        return

    var deadline = Time.get_ticks_msec() + 20 * 60 * 1000
    while busy and rpc != null and rpc.running:
        if Time.get_ticks_msec() >= deadline:
            await rpc.command({"type": "abort"}, 10.0)
            _fail("Pi agent run exceeded the 20 minute host deadline.")
            return
        if bool(get_meta("_pi_settled", false)):
            remove_meta("_pi_settled")
            break
        await get_tree().process_frame

    if rpc == null or not rpc.running:
        _fail(last_error if last_error != "" else "Pi process stopped unexpectedly.")
        return
    if last_error != "":
        _fail(last_error)
        return

    var last: Dictionary = await rpc.command({"type": "get_last_assistant_text"}, 15.0)
    var final_text = ""
    if bool(last.get("success", false)):
        final_text = str(last.get("data", {}).get("text", "")).strip_edges()
    if final_text == "":
        final_text = "Done."
    transcript.append(game_name, "assistant", final_text)
    if not streamed_text:
        assistant_message.emit(final_text)
    await _refresh_context_usage()
    await _maybe_auto_compact("after_turn")
    status_changed.emit("Ready")
    busy = false
    finished.emit(true)

func compact_now() -> Dictionary:
    if busy:
        return {"ok": false, "error": "Agent is busy."}
    busy = true
    var ready = await _ensure_runtime()
    if not bool(ready.get("ok", false)):
        busy = false
        return ready
    status_changed.emit("Compacting Pi session…")
    var response: Dictionary = await rpc.command({"type": "compact"}, 300.0)
    busy = false
    status_changed.emit("Ready")
    if not bool(response.get("success", false)):
        return {"ok": false, "error": str(response.get("error", "Pi compaction failed."))}
    var data: Dictionary = response.get("data", {})
    last_context_tokens = int(data.get("estimatedTokensAfter", 0))
    return {
        "ok": true,
        "summary": str(data.get("summary", "")),
        "tokens_before": int(data.get("tokensBefore", 0)),
        "tokens_after": int(data.get("estimatedTokensAfter", 0))
    }

func restart_runtime() -> void:
    if rpc != null:
        rpc.shutdown()
        rpc.queue_free()
    rpc = null
    runtime_config = {}
    bridge_dir = ""

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

    var auto_off: Dictionary = await rpc.command({"type": "set_auto_compaction", "enabled": false}, 15.0)
    if not bool(auto_off.get("success", false)):
        return {"ok": false, "error": "Could not configure Pi compaction policy: " + str(auto_off.get("error", ""))}
    await _refresh_context_usage()
    return {"ok": true}

func _refresh_context_usage() -> void:
    if rpc == null or not rpc.running:
        return
    var stats: Dictionary = await rpc.command({"type": "get_session_stats"}, 15.0)
    if not bool(stats.get("success", false)):
        return
    var usage = stats.get("data", {}).get("contextUsage", null)
    if typeof(usage) == TYPE_DICTIONARY:
        var tokens = usage.get("tokens", null)
        if tokens != null:
            last_context_tokens = int(tokens)

func _maybe_auto_compact(phase: String) -> void:
    var threshold = maxi(0, int(metadata.global_settings().get("compaction_auto_tokens", 100000)))
    if threshold <= 0:
        return
    await _refresh_context_usage()
    if last_context_tokens <= 0 or last_context_tokens < threshold:
        return
    status_changed.emit("Auto-compacting Pi session…")
    AppLoggerScript.game_event(game_name, "pi.compaction.auto", "phase=%s context_tokens=%d threshold=%d" % [phase, last_context_tokens, threshold])
    var response: Dictionary = await rpc.command({"type": "compact"}, 300.0)
    if bool(response.get("success", false)):
        last_context_tokens = int(response.get("data", {}).get("estimatedTokensAfter", 0))
    else:
        AppLoggerScript.game_event(game_name, "pi.compaction.error", str(response.get("error", "unknown")), "WARN")

func _on_pi_record(record: Dictionary) -> void:
    var type = str(record.get("type", ""))
    match type:
        "message_update":
            var event: Dictionary = record.get("assistantMessageEvent", {})
            var event_type = str(event.get("type", ""))
            if event_type == "text_delta":
                var delta = str(event.get("delta", ""))
                if delta != "":
                    streamed_text = true
                    llm_stream_delta.emit("assistant", delta)
            elif event_type == "text_end":
                llm_stream_end.emit("assistant")
            elif event_type == "thinking_delta":
                var thinking = str(event.get("delta", ""))
                if thinking != "":
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
                rpc.command({"type": "abort"}, 10.0)
        "message_end":
            var message: Dictionary = record.get("message", {})
            if str(message.get("role", "")) == "assistant" and str(message.get("stopReason", "")) == "error":
                last_error = str(message.get("errorMessage", "Pi provider request failed."))
        "auto_retry_start":
            status_changed.emit("Pi retry %d/%d…" % [int(record.get("attempt", 1)), int(record.get("maxAttempts", 3))])
            AppLoggerScript.game_event(game_name, "pi.retry", JSON.stringify(record), "WARN")
        "compaction_start":
            status_changed.emit("Pi is compacting context…")
            AppLoggerScript.game_event(game_name, "pi.compaction.start", JSON.stringify(record))
        "compaction_end":
            AppLoggerScript.game_event(game_name, "pi.compaction.end", JSON.stringify(record))
        "entry_appended":
            var entry: Dictionary = record.get("entry", {})
            if str(entry.get("customType", "")) == "gamesmith-verifier-failed":
                last_error = "The model repeatedly tried to finish without satisfying GameSmith's build/reload verification."
        "agent_settled":
            set_meta("_pi_settled", true)
        _:
            pass

func _on_pi_stderr(text: String) -> void:
    AppLoggerScript.game_event(game_name, "pi.stderr", text, "WARN")

func _service_host_bridge() -> void:
    if bridge_dir == "":
        return
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
        if command in ["reload_game", "read_runtime_log"]:
            result = tools.execute(command, request.get("args", {}))
        else:
            result = {"ok": false, "error": "Unknown GameSmith host bridge command: " + command}
        var response_path = bridge_dir.path_join("response-%s.json" % str(request.get("id", "")))
        var tmp = response_path + ".tmp"
        var out = FileAccess.open(tmp, FileAccess.WRITE)
        if out != null:
            out.store_string(JSON.stringify(result))
            out.close()
            DirAccess.rename_absolute(tmp, response_path)

func _fail(message: String) -> void:
    AppLoggerScript.game_event(game_name, "pi.failed", message, "ERROR")
    transcript.append(game_name, "assistant", "Error: " + message)
    assistant_message.emit("Error: " + message)
    status_changed.emit("Ready")
    busy = false
    finished.emit(false)

func _snippet(text: String) -> String:
    var flat = text.replace("\r", " ").replace("\n", " ").strip_edges()
    if flat.length() <= 80:
        return flat
    return flat.left(80) + "…"
