extends "res://src/agent/opencode_agent_controller.gd"

func _harness_name() -> String:
    return "Codex"

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
    for file in ["worker.mjs", "server.mjs", "protocol.mjs", "tools.mjs"]:
        if not JsonStore.write_bytes_atomic(directory.path_join(file), FileAccess.get_file_as_bytes("res://tools/codex/" + file)):
            return {"ok": false, "error": "Could not prepare Codex integration: " + file}
    for pair in [["workspace-paths.mjs", "pi/workspace-paths.mjs"], ["host-tools.mjs", "opencode/host-tools.mjs"], ["process-tree.mjs", "agent/process-tree.mjs"]]:
        if not JsonStore.write_bytes_atomic(directory.path_join(pair[0]), FileAccess.get_file_as_bytes("res://tools/" + pair[1])):
            return {"ok": false, "error": "Could not prepare Codex integration: " + pair[0]}
    var prompt = PiRuntimeConfigScript._game_prompt().replace("Pi's read/edit/write/grep/find/ls", "gamesmith_read/edit/write/search/list").replace("Pi's", "Codex's").replace("Pi process", "Codex process")
    prompt += "\nAll GameSmith tools are native dynamic tools named gamesmith_<command>, including gamesmith_start_test_game, gamesmith_reload_game, and gamesmith_git_commit. Use gamesmith_read with 1-based offset/limit, gamesmith_edit with path/old_text/new_text, gamesmith_write with path/content, gamesmith_search with a literal pattern, and gamesmith_list for files. Native shell, delegation and native file-write approvals are unavailable; use the GameSmith tools. Model, reasoning and automatic compaction are managed by your Codex configuration.\n"
    if not JsonStore.write_bytes_atomic(directory.path_join("prompt.md"), prompt.to_utf8_buffer()):
        return {"ok": false, "error": "Could not write Codex game instructions."}
    var session_file = absolute.path_join("session.json")
    var saved = JsonStore.read_dict(session_file, {})
    last_context_tokens = int(saved.context_tokens) if saved.get("context_tokens") != null else 0
    var config = {"workspace": ProjectSettings.globalize_path(tools.workspace), "bridge_dir": bridge,
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
    rpc.process_stopped.connect(func(message): last_error = message.replace("Pi", "Codex adapter"))
    return rpc.start(config)

func compact_now() -> Dictionary:
    return {"ok": false, "error": "Codex manages its own compaction."}
