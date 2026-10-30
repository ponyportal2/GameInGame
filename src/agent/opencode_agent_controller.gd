extends "res://src/agent/native_agent_controller.gd"

const STOP_GRACE_MS = 5000
var cancel_deadline := 0
var cancelling = false

func start_new_session() -> Dictionary:
    if busy: return {"ok": false, "error": "Stop OpenCode before starting a new session."}
    if not acquire_editor(): return {"ok": false, "error": last_error}
    # Archive only GameSmith's reference; native history stays with OpenCode.
    var directory = ProjectSettings.globalize_path(metadata.game_meta_dir(game_name).path_join("opencode"))
    var session_file = directory.path_join("session.json")
    var archive = ""
    if FileAccess.file_exists(session_file):
        archive = directory.path_join("session.previous-%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        if DirAccess.rename_absolute(session_file, archive) != OK:
            return {"ok": false, "error": "Could not preserve the previous OpenCode session reference. No session was reset."}
    restart_runtime()
    backend_pid = -1
    return {"ok": true, "archive": archive}

func cancel() -> void:
    if tools != null: tools.cancel_reload()
    if tools != null and is_instance_valid(tools.image_supervisor):
        tools.image_supervisor.stop_all()
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
    var assembled = HarnessInventory.assemble_runtime(_harness_id(), directory)
    if not assembled.ok: return assembled
    var prompt = _native_prompt()
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write " + _harness_name() + " game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge, "blender_enabled": _blender_enabled(),
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

func compact_now() -> Dictionary:
    return {"ok": false, "error": _harness_name() + " manages its own compaction."}

func _retire_after_cancel() -> bool:
    return false

func _native_prompt() -> String:
    var confined := _harness_id() == "opencode"
    var native_tools := "read/edit/write/grep/glob" if confined else "read/edit/write/grep/glob/list/apply_patch"
    var unavailable := "Shell, delegation, web access and file patches are unavailable; use the native read, glob, grep, write and edit tools for files." if confined else "Shell, delegation and web access are unavailable; use native read/write/edit/apply_patch tools for files."
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", _harness_name() + "'s " + native_tools).replace("Pi's", _harness_name() + "'s").replace("Pi process", _harness_name() + " process")
    prompt += "\nGameSmith tools are exposed by native MCP with the gamesmith_ prefix (for example gamesmith_start_test_game and gamesmith_reload_game). Use those tools for game testing, reload, and Git. " + unavailable + " If " + _harness_name() + " says a GameSmith result was saved outside the workspace, do not attempt to read that path. Retry the GameSmith operation with narrower filters, fewer requested properties, a smaller limit and its pagination; do not repeat an already-applied mutation blindly.\n"
    return prompt
