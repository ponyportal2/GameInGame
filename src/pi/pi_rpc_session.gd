class_name PiRpcSession
extends Node

signal record_received(record: Dictionary)
signal stderr_line(text: String)
signal process_stopped(message: String)

var stdio: FileAccess
var stderr: FileAccess
var pid := -1
var running := false
var stdout_buffer := ""
var stderr_buffer := ""
var responses: Dictionary = {}
var next_id := 1
var stop_message := ""
var writing := false

func start(config: Dictionary) -> Dictionary:
    if running:
        return {"ok": true}
    var availability = _check_pi_available()
    if not bool(availability.get("ok", false)):
        return availability
    var command = _command_line(config)
    var env_changes = {
        "GAMESMITH_HOST_BRIDGE_DIR": str(config.bridge_dir),
        "GAMESMITH_LEGACY_TRANSCRIPT": str(config.legacy_transcript),
        "GAMESMITH_LLM_DELAY_MS": str(config.llm_delay_ms),
        "GAMESMITH_MODEL_CACHE_PATH": ProjectSettings.globalize_path("user://host/openrouter-models.json"),
        "GAMESMITH_MODEL_PROVIDER": str(config.get("source_provider", "custom"))
    }
    if not bool(config.get("use_global_pi_auth", false)):
        env_changes["PI_CODING_AGENT_DIR"] = str(config.agent_dir)
    if str(config.get("api_key", "")) != "":
        env_changes["GAMESMITH_PI_API_KEY"] = str(config.api_key)
    var old_env := {}
    for key in env_changes:
        old_env[key] = {"had": OS.has_environment(key), "value": OS.get_environment(key)}
        OS.set_environment(key, str(env_changes[key]))

    var launched: Dictionary
    if OS.get_name() == "Windows":
        launched = OS.execute_with_pipe("cmd.exe", PackedStringArray(["/D", "/S", "/C", command]), false)
    else:
        launched = OS.execute_with_pipe("/bin/sh", PackedStringArray(["-lc", command]), false)

    for key in env_changes:
        if bool(old_env[key].had):
            OS.set_environment(key, str(old_env[key].value))
        else:
            OS.unset_environment(key)

    if launched.is_empty():
        return {"ok": false, "error": "Could not start global pi executable. Install Pi so the 'pi' command is available on PATH."}
    stdio = launched.get("stdio")
    stderr = launched.get("stderr")
    pid = int(launched.get("pid", -1))
    if stdio == null or pid <= 0:
        return {"ok": false, "error": "Pi process started without usable RPC pipes."}
    running = true
    process_mode = Node.PROCESS_MODE_ALWAYS
    return {"ok": true, "pid": pid}

func command(record: Dictionary) -> Dictionary:
    if not running:
        return {"success": false, "error": stop_message if stop_message != "" else "Pi RPC process is not running."}
    var id = "gs-%d" % next_id
    next_id += 1
    var payload = record.duplicate(true)
    payload["id"] = id
    responses.erase(id)
    var err = await _write_json(payload)
    if err != OK:
        return {"success": false, "error": "Could not write Pi RPC command (%d)." % err}
    while running and not responses.has(id):
        await get_tree().process_frame
    if not responses.has(id):
        return {"success": false, "error": stop_message if stop_message != "" else "Pi stopped before responding."}
    var response: Dictionary = responses[id]
    responses.erase(id)
    return response

func shutdown() -> void:
    running = false
    stop_message = "Pi runtime stopped."
    if stdio != null:
        stdio.close()
    if stderr != null:
        stderr.close()
    if pid > 0 and OS.is_process_running(pid):
        if OS.get_name() == "Windows":
            # cmd.exe launches npm's Pi shim, so killing only cmd leaves Node alive.
            var output: Array = []
            OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"], output, true)
        if OS.is_process_running(pid):
            OS.kill(pid)
    stdio = null
    stderr = null
    pid = -1
    running = false

func retire() -> void:
    shutdown()
    # Let pending command coroutines observe shutdown before freeing their node.
    if is_inside_tree():
        await get_tree().process_frame
    queue_free()

func _exit_tree() -> void:
    shutdown()

func _process(_delta: float) -> void:
    if not running:
        return
    _drain_pipe(stdio, false)
    _drain_pipe(stderr, true)
    if pid > 0 and not OS.is_process_running(pid):
        _drain_pipe(stdio, false)
        _drain_pipe(stderr, true)
        running = false
        stop_message = "Pi process exited with code %d." % OS.get_process_exit_code(pid)
        process_stopped.emit(stop_message)

func _drain_pipe(pipe: FileAccess, is_stderr: bool) -> void:
    if pipe == null:
        return
    # Pipe-backed FileAccess exposes unread bytes through get_length() in Godot 4.7.
    var available = pipe.get_length()
    if available <= 0:
        return
    var text = pipe.get_buffer(available).get_string_from_utf8()
    if is_stderr:
        stderr_buffer += text
        stderr_buffer = _consume_lines(stderr_buffer, true)
    else:
        stdout_buffer += text
        stdout_buffer = _consume_lines(stdout_buffer, false)

func _consume_lines(buffer: String, is_stderr: bool) -> String:
    var remaining = buffer
    while true:
        var newline = remaining.find("\n")
        if newline < 0:
            return remaining
        var line = remaining.left(newline)
        if line.ends_with("\r"):
            line = line.left(line.length() - 1)
        remaining = remaining.substr(newline + 1)
        if line == "":
            continue
        if is_stderr:
            stderr_line.emit(line)
            continue
        var parsed = JSON.parse_string(line)
        if typeof(parsed) != TYPE_DICTIONARY:
            stderr_line.emit("Pi emitted invalid RPC JSON: " + line.left(1000))
            continue
        var record: Dictionary = parsed
        if str(record.get("type", "")) == "response" and record.has("id"):
            responses[str(record.id)] = record
        record_received.emit(record)
    return remaining

func _write_json(record: Dictionary) -> Error:
    while writing and running:
        await get_tree().process_frame
    if stdio == null or not running:
        return ERR_UNAVAILABLE
    writing = true
    var bytes = (JSON.stringify(record) + "\n").to_utf8_buffer()
    # Nonblocking Windows pipes can reject a single large prompt write. Send
    # bounded chunks and let Pi drain between them; serialize complete records.
    for offset in range(0, bytes.size(), 1024):
        await get_tree().process_frame
        if stdio == null or not running:
            writing = false
            return ERR_UNAVAILABLE
        stdio.store_buffer(bytes.slice(offset, mini(offset + 1024, bytes.size())))
        var error = stdio.get_error()
        if error != OK:
            writing = false
            return error
    stdio.flush()
    var error = stdio.get_error()
    writing = false
    return error

func _check_pi_available() -> Dictionary:
    var configured = OS.get_environment("GAMESMITH_PI_BIN").strip_edges()
    if configured != "":
        if configured.contains("/") or configured.contains("\\"):
            if FileAccess.file_exists(configured):
                return {"ok": true}
            return {"ok": false, "error": "Configured Pi executable does not exist: %s. Set GAMESMITH_PI_BIN to a valid executable, or install with: npm install -g @earendil-works/pi-coding-agent@1.0.0" % configured}
        var configured_out: Array = []
        var configured_code = OS.execute("/bin/sh", PackedStringArray(["-lc", "command -v " + configured]), configured_out, true) if OS.get_name() != "Windows" else OS.execute("cmd.exe", PackedStringArray(["/D", "/S", "/C", "where " + configured]), configured_out, true)
        if configured_code == 0:
            return {"ok": true}
        return {"ok": false, "error": "Configured Pi command was not found on PATH: %s. Set GAMESMITH_PI_BIN to a valid command, or install with: npm install -g @earendil-works/pi-coding-agent@1.0.0" % configured}

    var output: Array = []
    var code: int
    if OS.get_name() == "Windows":
        code = OS.execute("cmd.exe", PackedStringArray(["/D", "/S", "/C", "where pi"]), output, true)
    else:
        code = OS.execute("/bin/sh", PackedStringArray(["-lc", "command -v pi"]), output, true)
    if code == 0:
        return {"ok": true}
    return {"ok": false, "error": "Global Pi executable was not found on PATH. Install with: npm install -g @earendil-works/pi-coding-agent@1.0.0. If Pi is installed elsewhere, set GAMESMITH_PI_BIN."}

func _command_line(config: Dictionary) -> String:
    var pi_bin = OS.get_environment("GAMESMITH_PI_BIN").strip_edges()
    if pi_bin == "":
        pi_bin = "pi"
    var args: Array[String] = [
        "--mode", "rpc",
        "--session-dir", str(config.session_dir),
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--no-themes",
        "--no-context-files",
        "--append-system-prompt", str(config.prompt_path),
        "--no-builtin-tools",
        "--tools", "read,edit,write,grep,find,ls,delete_path,move_path,git_status,git_diff,git_log,git_commit,reload_game,read_runtime_log,start_test_game,read_test_log,stop_test_game,test_game_action",
        "--extension", str(config.extension_path),
        "--approve"
    ]
    var session_file = _resume_session_file(str(config.session_dir))
    if session_file != "":
        # Pi's session-id lookup is scoped to the original cwd in its header.
        # Explicitly open the persisted file so a workspace rename keeps history.
        args.append_array(["--session", session_file])
    else:
        args.append_array(["--session-id", "gamesmith"])

    if OS.get_name() == "Windows":
        var command = "cd /D " + _quote_windows(str(config.workspace)) + " && " + _quote_windows(pi_bin)
        for arg in args:
            command += " " + _quote_windows(arg)
        return command

    var command = "cd " + _quote_unix(str(config.workspace)) + " && exec " + _quote_unix(pi_bin)
    for arg in args:
        command += " " + _quote_unix(arg)
    return command

func _resume_session_file(session_dir: String) -> String:
    var dir = DirAccess.open(session_dir)
    if dir == null:
        return ""
    var latest = ""
    var latest_time = -1
    for name in dir.get_files():
        if not name.ends_with(".jsonl"):
            continue
        var path = session_dir.path_join(name)
        var file = FileAccess.open(path, FileAccess.READ)
        if file == null:
            continue
        var header = JSON.parse_string(file.get_line())
        file.close()
        if typeof(header) != TYPE_DICTIONARY or str(header.get("type", "")) != "session":
            continue
        var modified = FileAccess.get_modified_time(path)
        if modified > latest_time or (modified == latest_time and path > latest):
            latest = path
            latest_time = modified
    return latest

func _quote_windows(value: String) -> String:
    return "\"" + value.replace("\"", "\"\"") + "\""

func _quote_unix(value: String) -> String:
    return "'" + value.replace("'", "'\"'\"'") + "'"
