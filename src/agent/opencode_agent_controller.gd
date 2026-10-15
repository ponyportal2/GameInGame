extends "res://src/agent/command_code_agent_controller.gd"

const STOP_GRACE_MS = 5000
var cancel_deadline := 0
var cancelling = false

func cancel() -> void:
    if tools != null and is_instance_valid(tools.blender_supervisor):
        tools.blender_supervisor.stop_all()
    if not busy or cancelling:
        return
    recovery_generation += 1
    recovery_active = false
    cancelling = true
    cancel_deadline = Time.get_ticks_msec() + STOP_GRACE_MS
    operation_id += 1
    restart_after_finish = false
    var cancelled_result = {"ok": false, "cancelled": true, "error": "Cancelled by the player."}
    if not pending_reload.is_empty():
        _write_host_response(pending_reload.bridge_dir, pending_reload.request, cancelled_result)
    for pending in pending_test_commands:
        _write_host_response(pending.bridge_dir, pending.request, cancelled_result)
    for pending in pending_blender_commands:
        _write_host_response(pending.bridge_dir, pending.request, cancelled_result)
    pending_blender_commands.clear()
    blender_grants.clear()
    _clear_pending_reload()
    pending_test_commands.clear()
    if tools != null and is_instance_valid(tools.test_supervisor):
        tools.test_supervisor.stop_all()
    status_changed.emit("Stopping " + _harness_name() + "...")
    var result: Dictionary = {"success": false}
    if rpc != null and rpc.running:
        result = await rpc.command({"type": "cancel"})
    if not result.get("success", false) or _retire_after_cancel():
        restart_runtime()
    cancelling = false
    busy = false
    last_error = ""
    pending_provider_error = ""
    llm_stream_end.emit("assistant")
    llm_stream_end.emit("thinking")
    assistant_message.emit("Cancelled. File edits already made were kept.")
    status_changed.emit("Ready")
    finished.emit(false)

func _process(delta: float) -> void:
    super._process(delta)
    if cancelling and Time.get_ticks_msec() >= cancel_deadline:
        AppLoggerScript.game_event(game_name, _harness_name().to_lower() + ".cancel.forced", "Native cancellation did not settle within the Stop grace period; terminating the backend tree.", "WARN")
        restart_runtime()

func _harness_name() -> String:
    return "OpenCode"

func _harness_id() -> String:
    return "opencode"

func _start_command_runtime() -> Dictionary:
    if not acquire_editor(): return {"ok": false, "error": last_error}
    if rpc != null and rpc.running:
        return {"ok": true}
    if rpc != null:
        rpc.retire()
        rpc = null
    var directory = metadata.game_meta_dir(game_name).path_join(_harness_id())
    var absolute = ProjectSettings.globalize_path(directory)
    var bridge = absolute.path_join("bridge-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    DirAccess.make_dir_recursive_absolute(bridge)
    for file in ["worker.mjs", "server.mjs", "events.mjs", "protocol.mjs", "gamesmith.mjs", "mcp.mjs", "host-tools.mjs"]:
        if not JsonStore.write_bytes_atomic(directory.path_join(file), FileAccess.get_file_as_bytes("res://tools/opencode/" + file)):
            return {"ok": false, "error": "Could not prepare " + _harness_name() + " integration: " + file}
    if not JsonStore.write_bytes_atomic(directory.path_join("workspace-paths.mjs"), FileAccess.get_file_as_bytes("res://tools/pi/workspace-paths.mjs")):
        return {"ok": false, "error": "Could not prepare " + _harness_name() + " workspace policy."}
    var prompt = PiRuntimeConfigScript._game_prompt().replace("Pi's read/edit/write/grep/find/ls", _harness_name() + "'s read/edit/write/grep/glob/list").replace("Pi's", _harness_name() + "'s").replace("Pi process", _harness_name() + " process")
    prompt += "\nGameSmith tools are exposed by native MCP with the gamesmith_ prefix (for example gamesmith_start_test_game and gamesmith_reload_game). Use those tools for game testing, reload, and Git. Shell and delegation are unavailable; use native read/write/edit/apply_patch tools for files.\n"
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write " + _harness_name() + " game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge,
        "plugin": absolute.path_join("gamesmith.mjs"), "mcp": absolute.path_join("mcp.mjs"),
        "worker": absolute.path_join("worker.mjs"), "prompt_path": absolute.path_join("prompt.md"),
        "label": _harness_name(), "harness": _harness_id(), "name": game_name, "context_tokens": saved.get("context_tokens"),
        "session": saved.get("session", ""), "session_file": session_file,
        "config_path": absolute.path_join("runtime.json")}
    if not JsonStore.write_dict(config.config_path, config):
        return {"ok": false, "error": "Could not write " + _harness_name() + " runtime configuration."}
    bridge_dir = bridge
    rpc = CommandSession.new()
    add_child(rpc)
    rpc.record_received.connect(_on_command_record)
    rpc.stderr_line.connect(func(line): AppLoggerScript.game_event(game_name, _harness_id() + ".stderr", line, "WARN"))
    rpc.process_stopped.connect(func(message): last_error = message.replace("Pi", _harness_name() + " adapter"))
    return rpc.start(config)

func _maybe_auto_compact(_phase: String) -> void:
    pass

func compact_now() -> Dictionary:
    return {"ok": false, "error": _harness_name() + " manages its own compaction."}

func _retire_after_cancel() -> bool:
    return false
