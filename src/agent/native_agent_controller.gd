extends "res://src/agent/agent_controller_base.gd"

# GameSmith-side native request/result lifecycle. Concrete controllers retain
# transport construction, native sessions, permissions and cancellation policy.

const HarnessInventory = preload("res://src/agent/harness_inventory.gd")
const GamePromptScript = preload("res://src/agent/game_prompt.gd")

const CommandSession = preload("res://src/agent/command_code_session.gd")

var result_corrected := false
var result_received := false
var result_text := ""
var backend_pid := -1

func _send_player_attempt(text: String) -> void:
    if busy:
        return
    if not acquire_editor():
        assistant_message.emit(last_error)
        finished.emit(false)
        return
    busy = true
    operation_id += 1
    var operation = operation_id
    result_corrected = false
    result_received = false
    result_text = ""
    last_error = ""
    streamed_text = false
    status_changed.emit("Starting " + _harness_name() + "…")
    var ready = _start_command_runtime()
    _record_player_request(text)
    if not ready.get("ok", false):
        initialization_failed = true
        _fail(str(ready.get("error", _harness_name() + " is unavailable.")))
        return
    await _maybe_auto_compact("before_request")
    if operation != operation_id:
        return
    if auto_compaction_failed_operation == operation:
        recovery_active = false
        _fail("Could not compact the conversation before this request. History and edits were kept. Retry Compact now before continuing.")
        return
    status_changed.emit(_harness_name() + " is working…")
    var accepted: Dictionary = await rpc.command({"type": "prompt", "message": text})
    if operation != operation_id:
        return
    if not accepted.get("success", false):
        request_preserved = bool(accepted.get("request_preserved", true))
        initialization_failed = bool(accepted.get("initialization_failed", false))
        restart_after_finish = initialization_failed or bool(accepted.get("runtime_failed", false))
        _fail(str(accepted.get("error", _harness_name() + " rejected the request.")))
        return
    request_admitted = true
    while operation == operation_id and not result_received and rpc != null and rpc.running:
        await get_tree().process_frame
    if operation != operation_id:
        return
    llm_stream_end.emit("assistant")
    llm_stream_end.emit("thinking")
    if not result_received or last_error != "":
        _fail(last_error if last_error != "" else _harness_name() + " stopped unexpectedly.")
        return
    if result_text != "":
        transcript.append(game_name, "assistant", result_text)
        if result_corrected:
            transcript_reconciled.emit()
        elif not streamed_text:
            assistant_message.emit(result_text)
    await _maybe_auto_compact("after_turn")
    if operation != operation_id:
        return
    busy = false
    status_changed.emit("Ready")
    finished.emit(true)

func _on_command_record(record: Dictionary) -> void:
    match str(record.get("type", "")):
        "backend":
            backend_pid = int(record.get("pid", -1))
        "delta":
            var kind = str(record.get("kind", "assistant"))
            if kind == "assistant":
                streamed_text = true
            llm_stream_delta.emit(kind, str(record.get("text", "")))
        "stream_end":
            llm_stream_end.emit("assistant")
            llm_stream_end.emit("thinking")
        "tool":
            llm_snippet.emit("tool", str(record.get("name", "")) + " " + str(record.get("description", "")))
            status_changed.emit("Running %s…" % str(record.get("name", "tool")))
        "status":
            status_changed.emit(str(record.get("text", "")))
        "context":
            last_context_tokens = int(record.tokens) if record.get("tokens") != null else 0
        "complete":
            request_preserved = bool(record.get("request_preserved", true))
            initialization_failed = bool(record.get("initialization_failed", false))
            restart_after_finish = initialization_failed or bool(record.get("runtime_failed", false))
            result_corrected = bool(record.get("corrected", false))
            result_received = true
            result_text = str(record.get("text", ""))
            if not record.get("ok", false):
                last_error = str(record.get("error", _harness_name() + " request failed."))
                if last_error == "": last_error = _harness_name() + " request failed."

func settings_changed() -> void:
    # Native harnesses own their settings. Host preference changes must not
    # restart their existing conversations or override native configuration.
    pass

func approve_reload() -> void:
    super.approve_reload()
    if busy:
        status_changed.emit(_harness_name() + " is working…")

func _fail(message: String) -> void:
    last_error = message
    super._fail(message)

func _start_command_runtime() -> Dictionary:
    return {"ok": false, "error": "This native controller does not implement runtime construction."}

func _maybe_auto_compact(_phase: String) -> void:
    # Only Command-code currently supports host-triggered native compaction.
    pass

func _harness_name() -> String:
    return "Native agent"
