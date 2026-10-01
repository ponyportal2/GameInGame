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

func start(config: Dictionary) -> Dictionary:
    if running:
        return {"ok": true}
    var command = _command_line(config)
    var env_changes = {
        "GAMESMITH_HOST_BRIDGE_DIR": str(config.bridge_dir),
        "GAMESMITH_LEGACY_TRANSCRIPT": str(config.legacy_transcript),
        "GAMESMITH_LLM_DELAY_MS": str(config.llm_delay_ms)
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

func command(record: Dictionary, timeout_sec: float = 300.0) -> Dictionary:
    if not running:
        return {"success": false, "error": stop_message if stop_message != "" else "Pi RPC process is not running."}
    var id = "gs-%d" % next_id
    next_id += 1
    var payload = record.duplicate(true)
    payload["id"] = id
    responses.erase(id)
    var err = _write_json(payload)
    if err != OK:
        return {"success": false, "error": "Could not write Pi RPC command (%d)." % err}
    var deadline = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
    while running and not responses.has(id):
        if Time.get_ticks_msec() >= deadline:
            return {"success": false, "error": "Timed out waiting for Pi RPC response to %s." % str(record.get("type", "command"))}
        await get_tree().process_frame
    if not responses.has(id):
        return {"success": false, "error": stop_message if stop_message != "" else "Pi stopped before responding."}
    var response: Dictionary = responses[id]
    responses.erase(id)
    return response

func shutdown() -> void:
    if stdio != null:
        stdio.close()
    if stderr != null:
        stderr.close()
    if pid > 0 and OS.is_process_running(pid):
        OS.kill(pid)
    stdio = null
    stderr = null
    pid = -1
    running = false

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
    if stdio == null:
        return ERR_UNAVAILABLE
    stdio.store_string(JSON.stringify(record) + "\n")
    stdio.flush()
    return stdio.get_error()

func _command_line(config: Dictionary) -> String:
    var pi_bin = OS.get_environment("GAMESMITH_PI_BIN").strip_edges()
    if pi_bin == "":
        pi_bin = "pi"
    var args: Array[String] = [
        "--mode", "rpc",
        "--session-dir", str(config.session_dir),
        "--session-id", "gamesmith",
        "--name", str(config.get("game_name", "GameSmith")),
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--no-themes",
        "--no-context-files",
        "--no-builtin-tools",
        "--tools", "read,edit,write,grep,find,ls,delete_path,move_path,git_status,git_diff,git_log,git_commit,reload_game,read_runtime_log",
        "--extension", str(config.extension_path),
        "--provider", str(config.provider),
        "--model", str(config.model),
        "--approve"
    ]
    var thinking = str(config.get("thinking", ""))
    if thinking != "":
        args.append("--thinking")
        args.append(thinking)

    if OS.get_name() == "Windows":
        var command = "cd /D " + _quote_windows(str(config.workspace)) + " && " + _quote_windows(pi_bin)
        for arg in args:
            command += " " + _quote_windows(arg)
        return command

    var command = "cd " + _quote_unix(str(config.workspace)) + " && exec " + _quote_unix(pi_bin)
    for arg in args:
        command += " " + _quote_unix(arg)
    return command

func _quote_windows(value: String) -> String:
    return "\"" + value.replace("\"", "\"\"") + "\""

func _quote_unix(value: String) -> String:
    return "'" + value.replace("'", "'\"'\"'") + "'"
