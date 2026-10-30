extends "res://src/agent/native_agent_controller.gd"

var compaction_attempted_operation := -1

func _start_command_runtime() -> Dictionary:
    if not acquire_editor(): return {"ok": false, "error": last_error}
    if rpc != null and rpc.running:
        return {"ok": true}
    if rpc != null:
        rpc.retire()
        rpc = null
    var directory = metadata.game_meta_dir(game_name).path_join("command-code")
    var absolute = ProjectSettings.globalize_path(directory)
    var bridge = absolute.path_join("bridge-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    DirAccess.make_dir_recursive_absolute(bridge)
    var assembled = HarnessInventory.assemble_runtime("command-code", directory)
    if not assembled.ok: return assembled
    var prompt = _native_prompt()
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write Command-code game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge, "blender_enabled": _blender_enabled(),
        "mod": absolute.path_join("gamesmith.ts"), "worker": absolute.path_join("worker.mjs"),
        "context_tokens": saved.get("context_tokens"),
        "prompt_path": absolute.path_join("prompt.md"), "name": game_name,
        "session_id": saved.get("session", ""),
        "session_file": session_file,
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

func compact_now() -> Dictionary:
    if not acquire_editor(): return {"ok": false, "error": last_error}
    if busy:
        return {"ok": false, "error": "Agent is busy."}
    busy = true
    operation_id += 1
    var operation = operation_id
    var ready = _start_command_runtime()
    if not ready.get("ok", false):
        busy = false
        return ready
    status_changed.emit("Compacting Command-code session…")
    var response: Dictionary = await rpc.command({"type": "compact"})
    if operation != operation_id:
        return {"ok": false, "cancelled": true, "error": "Compaction cancelled."}
    busy = false
    status_changed.emit("Ready")
    var result: Dictionary = response.get("data", {"ok": false, "error": response.get("error", "Command-code compaction failed.")})
    if result.get("no_op", false):
        result.ok = false
    return result

func _maybe_auto_compact(phase: String) -> void:
    var threshold = maxi(0, int(metadata.global_settings().get("compaction_auto_tokens", 100000)))
    if threshold <= 0 or last_context_tokens < threshold or compaction_attempted_operation == operation_id:
        return
    compaction_attempted_operation = operation_id
    var operation = operation_id
    status_changed.emit("Auto-compacting Command-code session…")
    AppLoggerScript.game_event(game_name, "command-code.compaction.auto", "phase=%s context_tokens=%d threshold=%d" % [phase, last_context_tokens, threshold])
    var response: Dictionary = await rpc.command({"type": "compact"})
    if operation != operation_id:
        return
    if not response.get("success", false) and not response.get("data", {}).get("no_op", false):
        auto_compaction_failed_operation = operation_id
        var message = "Automatic compaction failed: " + str(response.get("error", "unknown")) + ". Conversation history was kept."
        transcript.append(game_name, "system", message)
        assistant_message.emit(message)
        AppLoggerScript.game_event(game_name, "command-code.compaction.error", message, "WARN")

func _harness_name() -> String:
    return "Command-code"

func start_new_session() -> Dictionary:
    if busy: return {"ok": false, "error": "Stop Command-code before starting a new session."}
    if not acquire_editor(): return {"ok": false, "error": last_error}
    var directory = ProjectSettings.globalize_path(metadata.game_meta_dir(game_name).path_join("command-code"))
    var session_file = directory.path_join("session.json")
    var archive = ""
    if FileAccess.file_exists(session_file):
        archive = directory.path_join("session.previous-%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        if DirAccess.rename_absolute(session_file, archive) != OK:
            return {"ok": false, "error": "Could not preserve the previous Command-code session reference. No session was reset."}
    restart_runtime()
    last_context_tokens = 0
    backend_pid = -1
    return {"ok": true, "archive": archive}

func _native_prompt() -> String:
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "Command-code's read_file/edit_file/write_file/grep/glob/read_directory").replace("Pi's", "Command-code's").replace("Pi process", "Command-code process")
    return prompt
