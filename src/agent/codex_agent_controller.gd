extends "res://src/agent/opencode_agent_controller.gd"

func _harness_name() -> String:
    return "Codex"

func _on_command_record(record: Dictionary) -> void:
    if record.get("initialization_failed", false):
        restart_after_finish = true
    super._on_command_record(record)

func _fail(message: String) -> void:
    last_error = message
    super._fail(message)

func start_new_session() -> Dictionary:
    if busy: return {"ok": false, "error": "Stop Codex before starting a new session."}
    if not acquire_editor(): return {"ok": false, "error": last_error}
    var result = archive_session(metadata, game_name)
    if result.get("ok", false): restart_runtime()
    return result

static func archive_session(game_metadata, target_game: String) -> Dictionary:
    var directory = ProjectSettings.globalize_path(game_metadata.game_meta_dir(target_game).path_join("codex"))
    var session_file = directory.path_join("session.json")
    var archive = ""
    if FileAccess.file_exists(session_file):
        archive = directory.path_join("session.previous-%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        if DirAccess.rename_absolute(session_file, archive) != OK:
            return {"ok": false, "error": "Could not preserve the previous Codex session reference. No session was reset."}
    return {"ok": true, "archive": archive}

func _start_command_runtime() -> Dictionary:
    if not acquire_editor(): return {"ok": false, "error": last_error}
    if rpc != null and rpc.running:
        return {"ok": true}
    if rpc != null:
        rpc.retire()
        rpc = null
    var directory = metadata.game_meta_dir(game_name).path_join("codex")
    var absolute = ProjectSettings.globalize_path(directory)
    var bridge = absolute.path_join("bridge-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
    DirAccess.make_dir_recursive_absolute(bridge)
    var assembled = HarnessInventory.assemble_runtime("codex", directory)
    if not assembled.ok: return assembled
    var prompt = _native_prompt()
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write Codex game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge, "blender_enabled": _blender_enabled(),
        "worker": absolute.path_join("worker.mjs"), "prompt_path": absolute.path_join("prompt.md"),
        "label": "Codex", "name": game_name, "context_tokens": saved.get("context_tokens"),
        "session": saved.get("session", ""), "session_file": session_file,
        "config_path": absolute.path_join("runtime.json")}
    if not JsonStore.write_dict(config.config_path, config):
        return {"ok": false, "error": "Could not write Codex runtime configuration."}
    bridge_dir = bridge
    rpc = CommandSession.new()
    add_child(rpc)
    rpc.record_received.connect(_on_command_record)
    rpc.stderr_line.connect(func(line): AppLoggerScript.game_event(game_name, "codex.stderr", line, "WARN"))
    rpc.process_stopped.connect(func(message):
        if last_error == "": last_error = message.replace("Pi", "Codex adapter"))
    return rpc.start(config)

func compact_now() -> Dictionary:
    return {"ok": false, "error": "Codex manages its own compaction."}

func _native_prompt() -> String:
    var prompt = PiRuntimeConfigScript._game_prompt(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "gamesmith_read/edit/write/search/list").replace("Pi's", "Codex's").replace("Pi process", "Codex process")
    prompt += "\nAll GameSmith tools are native dynamic tools named gamesmith_<command>, including gamesmith_start_test_game, gamesmith_reload_game, and gamesmith_git_commit. Use gamesmith_read with 1-based offset/limit, gamesmith_edit with path/old_text/new_text, gamesmith_write with path/content, gamesmith_search with a literal pattern, and gamesmith_list for files. Native shell, delegation and native file-write approvals are unavailable; use the GameSmith tools. Model, reasoning and automatic compaction are managed by your Codex configuration.\n"
    return prompt
