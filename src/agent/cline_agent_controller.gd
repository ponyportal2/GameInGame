extends "res://src/agent/opencode_agent_controller.gd"

var reload_grant := ""
var reload_grant_operation := -1

func _dispatch_host_request(request: Dictionary, directory: String) -> void:
    if not _uses_reload_grants():
        super._dispatch_host_request(request, directory)
        return
    var command = str(request.get("command", ""))
    if command == "authorize_reload":
        if not busy or cancelling or not pending_reload.is_empty():
            _write_host_response(directory, request, {"ok": false, "error": "Reload approval is unavailable."})
            return
        pending_reload = {"request": request, "bridge_dir": directory, "operation_id": operation_id}
        if bool(metadata.global_settings().get("auto_approve_reloads", false)):
            approve_reload()
        else:
            status_changed.emit("Waiting for reload approval")
            reload_approval_changed.emit(true)
        return
    if command == "reload_game":
        var token = str(request.get("args", {}).get("approval_token", ""))
        var result: Dictionary = {"ok": false, "error": "Reload requires a current, single-use ACP approval."}
        if busy and not cancelling and token != "" and token == reload_grant and reload_grant_operation == operation_id:
            reload_grant = ""
            status_changed.emit("Reloading game...")
            var reload_operation = operation_id
            result = await tools.wait_reload(tools.reload_game(func(): return reload_operation != operation_id or directory != bridge_dir or cancelling))
            if reload_operation != operation_id or directory != bridge_dir or cancelling: return
        _write_host_response(directory, request, result)
        return
    super._dispatch_host_request(request, directory)

func _uses_reload_grants() -> bool:
    return true

func approve_reload() -> void:
    if pending_reload.get("request", {}).get("command") != "authorize_reload":
        super.approve_reload()
        return
    var pending = pending_reload
    _clear_pending_reload()
    if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir or not busy or cancelling: return
    reload_grant = str(pending.request.get("args", {}).get("token", ""))
    reload_grant_operation = operation_id
    _write_host_response(bridge_dir, pending.request, {"ok": true})
    status_changed.emit(_harness_name() + " is working...")

func cancel() -> void:
    reload_grant = ""
    super.cancel()

func restart_runtime() -> void:
    reload_grant = ""
    super.restart_runtime()

func _harness_name() -> String:
    return "Cline"

func _on_command_record(record: Dictionary) -> void:
    if record.get("initialization_failed", false):
        restart_after_finish = true
    super._on_command_record(record)

func _fail(message: String) -> void:
    last_error = message
    super._fail(message)

func start_new_session() -> Dictionary:
    if busy: return {"ok": false, "error": "Stop " + _harness_name() + " before starting a new session."}
    if not acquire_editor(): return {"ok": false, "error": last_error}
    var directory = ProjectSettings.globalize_path(metadata.game_meta_dir(game_name).path_join(_native_directory_name()))
    var session_file = directory.path_join("session.json")
    var archive = ""
    if FileAccess.file_exists(session_file):
        archive = directory.path_join("session.previous-%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        if DirAccess.rename_absolute(session_file, archive) != OK:
            return {"ok": false, "error": "Could not preserve the previous " + _harness_name() + " session reference. No session was reset."}
    restart_runtime()
    return {"ok": true, "archive": archive}

func _start_command_runtime() -> Dictionary:
    if not acquire_editor(): return {"ok": false, "error": last_error}
    if rpc != null and rpc.running:
        return {"ok": true}
    if rpc != null:
        rpc.retire()
        rpc = null
    var directory = metadata.game_meta_dir(game_name).path_join(_native_directory_name())
    var absolute = ProjectSettings.globalize_path(directory)
    var bridge = absolute.path_join("bridge-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    DirAccess.make_dir_recursive_absolute(bridge)
    var assembled = HarnessInventory.assemble_runtime(_native_directory_name(), directory)
    if not assembled.ok: return assembled
    var prompt = _native_prompt()
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write " + _harness_name() + " game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge, "blender_enabled": _blender_enabled(),
        "worker": absolute.path_join("worker.mjs"), "mcp": absolute.path_join("mcp.mjs"), "prompt_path": absolute.path_join("prompt.md"),
        "label": _harness_name(), "name": game_name, "context_tokens": saved.get("context_tokens"),
        "session": saved.get("session", ""), "session_file": session_file,
        "config_path": absolute.path_join("runtime.json")}
    if not JsonStore.write_dict(config.config_path, config):
        return {"ok": false, "error": "Could not write " + _harness_name() + " runtime configuration."}
    bridge_dir = bridge
    rpc = CommandSession.new()
    add_child(rpc)
    rpc.record_received.connect(_on_command_record)
    rpc.stderr_line.connect(func(line): AppLoggerScript.game_event(game_name, _harness_name().to_lower() + ".stderr", line, "WARN"))
    rpc.process_stopped.connect(func(message):
        if last_error == "": last_error = message.replace("Pi", _harness_name() + " adapter"))
    return rpc.start(config)

func compact_now() -> Dictionary:
    return {"ok": false, "error": _harness_name() + " manages its own compaction."}

func _native_directory_name() -> String:
    return _harness_name().to_lower()


func _native_prompt() -> String:
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "gamesmith__read/edit/write/search/list").replace("Pi's", "Cline's").replace("Pi process", "Cline process")
    prompt += "\nAll GameSmith tools are MCP tools named gamesmith__<command>, including gamesmith__start_test_game, gamesmith__reload_game, and gamesmith__git_commit. Use gamesmith__read with 1-based offset/limit, gamesmith__edit with path/old_text/new_text, gamesmith__write with path/content, gamesmith__search with a literal pattern, and gamesmith__list for files. Native shell, delegation and native filesystem tools are denied; use only the GameSmith tools. Model, reasoning and compaction are managed by your Cline configuration.\n"
    prompt += "GameSmith file paths must be relative to the game workspace (for example main.gd), never absolute paths. For a headless startup check, read_test_log reporting state=running and load_result.ok=true means startup succeeded; latest_outcome=accepted also confirms acceptance. The test keeps running until you stop it: do not wait for it to finish by itself or repeatedly poll identical logs. Once your checks pass, call stop_test_game with its run_id, then use reload_game if a full reload is needed. A successful live parameter patch with set_properties needs no reload.\n"
    return prompt
