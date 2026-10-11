extends "res://src/agent/pi_agent_controller.gd"

const CommandSession = preload("res://src/agent/command_code_session.gd")
var result_received := false
var result_text := ""

func send_player_request(text: String) -> void:
    if busy:
        return
    busy = true
    operation_id += 1
    var operation = operation_id
    result_received = false
    result_text = ""
    last_error = ""
    streamed_text = false
    status_changed.emit("Starting Command-code…")
    var ready = _start_command_runtime()
    transcript.append(game_name, "user", text)
    if not ready.get("ok", false):
        _fail(str(ready.get("error", "Command-code is unavailable.")))
        return
    status_changed.emit("Command-code is working…")
    var accepted: Dictionary = await rpc.command({"type": "prompt", "message": text})
    if operation != operation_id:
        return
    if not accepted.get("success", false):
        _fail(str(accepted.get("error", "Command-code rejected the request.")))
        return
    while operation == operation_id and not result_received and rpc != null and rpc.running:
        await get_tree().process_frame
    if operation != operation_id:
        return
    llm_stream_end.emit("assistant")
    llm_stream_end.emit("thinking")
    if not result_received or last_error != "":
        _fail(last_error if last_error != "" else "Command-code stopped unexpectedly.")
        return
    if result_text != "":
        transcript.append(game_name, "assistant", result_text)
        if not streamed_text:
            assistant_message.emit(result_text)
    busy = false
    status_changed.emit("Ready")
    finished.emit(true)

func _start_command_runtime() -> Dictionary:
    if rpc != null and rpc.running:
        return {"ok": true}
    if rpc != null:
        rpc.retire()
        rpc = null
    var directory = metadata.game_meta_dir(game_name).path_join("command-code")
    var absolute = ProjectSettings.globalize_path(directory)
    var bridge = absolute.path_join("bridge-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    DirAccess.make_dir_recursive_absolute(bridge)
    for file in ["worker.mjs", "protocol.mjs", "gamesmith.ts"]:
        if not JsonStore.write_bytes_atomic(directory.path_join(file), FileAccess.get_file_as_bytes("res://tools/command-code/" + file)):
            return {"ok": false, "error": "Could not prepare Command-code integration: " + file}
    if not JsonStore.write_bytes_atomic(directory.path_join("workspace-paths.mjs"), FileAccess.get_file_as_bytes("res://tools/pi/workspace-paths.mjs")):
        return {"ok": false, "error": "Could not prepare Command-code workspace policy."}
    var prompt = PiRuntimeConfigScript._game_prompt().replace("Pi's read/edit/write/grep/find/ls", "Command-code's read_file/edit_file/write_file/grep/glob/read_directory").replace("Pi's", "Command-code's").replace("Pi process", "Command-code process")
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write Command-code game instructions."}
    var session_file = absolute.path_join("session.json")
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge,
        "mod": absolute.path_join("gamesmith.ts"), "worker": absolute.path_join("worker.mjs"),
        "prompt_path": absolute.path_join("prompt.md"), "name": game_name,
        "session": JsonStore.read_dict(session_file, {}).get("path", JsonStore.read_dict(session_file, {}).get("session", "")), "session_file": session_file,
        "config_path": absolute.path_join("runtime.json")}
    if not JsonStore.write_dict(config.config_path, config):
        return {"ok": false, "error": "Could not write Command-code runtime configuration."}
    bridge_dir = bridge
    rpc = CommandSession.new()
    add_child(rpc)
    rpc.record_received.connect(_on_command_record)
    rpc.stderr_line.connect(func(line): AppLoggerScript.game_event(game_name, "command-code.stderr", line, "WARN"))
    rpc.process_stopped.connect(func(message): last_error = message.replace("Pi", "Command-code adapter"))
    return rpc.start(config)

func _on_command_record(record: Dictionary) -> void:
    match str(record.get("type", "")):
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
        "complete":
            result_received = true
            result_text = str(record.get("text", ""))
            if not record.get("ok", false):
                last_error = str(record.get("error", "Command-code request failed."))

func compact_now() -> Dictionary:
    return {"ok": false, "error": "Command-code manages its own compaction."}

func settings_changed() -> void:
    pass

func approve_reload() -> void:
    super.approve_reload()
    if busy:
        status_changed.emit("Command-code is working…")
