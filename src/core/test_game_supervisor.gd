extends Node

# The host supervises liveness; no stop operation depends on a responsive child.
const Reader = preload("res://src/core/runtime_log_reader.gd")
const MAX_RUNS = 16
const RAW_CAPTURE_BYTES = 2 * 1024 * 1024
var grace_ms := 5000
var runs: Dictionary = {}
var workspace_path := ""

func rebind(workspace: String) -> void:
    var old_root = _test_root()
    workspace_path = workspace
    var new_root = _test_root()
    for run in runs.values():
        for key in ["path", "session_path", "user_data"]:
            if run.has(key) and str(run[key]).begins_with(old_root + "/"):
                run[key] = new_root + str(run[key]).trim_prefix(old_root)

func _test_root() -> String:
    return ProjectSettings.globalize_path("user://host/games".path_join(workspace_path.get_file()).path_join("tests"))

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func rendered_allowed() -> bool:
    return bool(MetadataStore.new().global_settings().get("allow_rendered_tests", false))

func has_running() -> bool:
    poll()
    for run in runs.values():
        if run.state != "exited":
            return true
    return false

func start(workspace: String, mode: String = "headless") -> Dictionary:
    if workspace_path == "":
        rebind(workspace)
    if mode not in ["headless", "rendered"]:
        return {"ok": false, "error": "Mode must be headless or rendered."}
    if mode == "rendered" and not rendered_allowed():
        return {"ok": false, "error": "Rendered testing is disabled in Settings. Headless testing is always available.", "rendered_allowed": false}
    if has_running():
        return {"ok": false, "error": "Stop the existing test before starting another."}
    var source = ProjectSettings.globalize_path(workspace)
    if not FileAccess.file_exists(source.path_join("main.gd")):
        return {"ok": false, "error": "No main.gd exists yet."}
    var id = Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "") + "-" + Crypto.new().generate_random_bytes(6).hex_encode()
    var path = ProjectSettings.globalize_path("user://host/games".path_join(workspace.get_file()).path_join("tests").path_join(id))
    var config = {"run_id": id, "workspace": source, "game": workspace.get_file(), "mode": mode, "control_dir": path, "diagnostics_root": path.get_base_dir().path_join("runtime")}
    if not JsonStore.write_dict(path.path_join("config.json"), config):
        return {"ok": false, "error": "Could not write test configuration."}
    var args = PackedStringArray()
    # Reuse the same project/PCK and engine, but never run the host's main scene.
    var project_path = ProjectSettings.globalize_path("res://")
    if project_path != "":
        args.append_array(["--path", project_path])
    else:
        # Godot consumes --main-pack before exposing get_cmdline_args(), and
        # packed res:// has no filesystem root. Resolve the shipped layout.
        var engine_dir = OS.get_executable_path().get_base_dir()
        var pack = ""
        for candidate in [OS.get_environment("GAMESMITH_HOST_PACK"), engine_dir.path_join("GameSmith.pck"), engine_dir.get_base_dir().path_join("GameSmith.pck")]:
            if candidate != "" and FileAccess.file_exists(candidate):
                pack = candidate
                break
        if pack == "":
            return {"ok": false, "error": "Could not locate GameSmith.pck for testing. Set GAMESMITH_HOST_PACK for a custom installation."}
        args.append_array(["--main-pack", pack])
    if mode == "headless":
        args.append("--headless")
    else:
        args.append_array(["--position", "80,80"])
    args.append_array(["--audio-driver", "Dummy", "--log-file", path.path_join("engine.log"), "--script", "res://src/core/test_game_process.gd", "--", path.path_join("config.json")])
    # Child user:// is separate. Changes last only through process creation.
    var saved: Dictionary = {}
    for key in ["APPDATA", "HOME", "XDG_DATA_HOME"]:
        saved[key] = OS.get_environment(key) if OS.has_environment(key) else null
        OS.set_environment(key, path.path_join("data"))
    var pipe = OS.execute_with_pipe(OS.get_executable_path(), args, false)
    for key in saved:
        if saved[key] == null:
            OS.unset_environment(key)
        else:
            OS.set_environment(key, saved[key])
    if pipe.is_empty():
        return {"ok": false, "error": "Could not launch the test process."}
    var run = {"ok": true, "run_id": id, "mode": mode, "pid": pipe.pid, "state": "starting", "path": path, "pipe": pipe, "stop_method": "", "stop_reason": "", "stop_deadline": 0, "action_pending": false, "rendered_allowed": rendered_allowed()}
    runs[id] = run
    while runs.size() > MAX_RUNS:
        runs.erase(runs.keys()[0])
    return _public(run)

func _process(_delta: float) -> void:
    poll()

func poll() -> void:
    for run in runs.values():
        if run.state == "exited":
            continue
        for channel in ["stdio", "stderr"]:
            var stream: FileAccess = run.pipe.get(channel)
            if stream != null:
                # Bounded work each frame; raw engine.log remains the full evidence.
                for i in range(8):
                    var bytes = stream.get_buffer(4096)
                    if bytes.is_empty():
                        break
                    var output = FileAccess.open(run.path.path_join(channel + ".log"), FileAccess.READ_WRITE if FileAccess.file_exists(run.path.path_join(channel + ".log")) else FileAccess.WRITE)
                    if output != null:
                        output.seek_end()
                        var available = maxi(0, RAW_CAPTURE_BYTES - output.get_length())
                        output.store_buffer(bytes.slice(0, available))
                        if bytes.size() > available:
                            run[channel + "_dropped_bytes"] = int(run.get(channel + "_dropped_bytes", 0)) + bytes.size() - available
        var child = _read_data(run.path.path_join("status.json"))
        for key in ["session_id", "session_path", "user_data", "load_result"]:
            if child.has(key):
                run[key] = child[key]
        if run.state == "starting" and child.get("state") == "running":
            run.state = "running"
        if run.action_pending and FileAccess.file_exists(run.path.path_join("action-result.json")):
            var action = _read_data(run.path.path_join("action-result.json"))
            if not action.is_empty():
                run.action_result = action
                run.action_pending = false
        if not OS.is_process_running(run.pid):
            run.state = "exited"
            run.exit_code = OS.get_process_exit_code(run.pid)
            if run.stop_method == "requested":
                run.stop_method = "graceful" if child.get("graceful_exit", false) else "unconfirmed"
            run.pipe.clear()
            _save_outcome(run)
        elif run.stop_deadline > 0 and Time.get_ticks_msec() >= run.stop_deadline:
            var error = OS.kill(run.pid)
            run.stop_method = "forced" if error == OK else "kill_failed"
            run.stop_reason = "Process did not exit after the graceful shutdown request; it may be hung or its control channel may have failed."
            run.stop_deadline = 0 if error == OK else Time.get_ticks_msec() + grace_ms
            _save_outcome(run)

func _save_outcome(run: Dictionary) -> void:
    var outcome = _public(run)
    outcome.erase("action_result")
    JsonStore.write_dict(run.path.path_join("outcome.json"), outcome)

func _read_data(path: String) -> Dictionary:
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parser = JSON.new()
    if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
        return {}
    return parser.data

func _public(run: Dictionary) -> Dictionary:
    var result = run.duplicate()
    for key in ["pipe", "stop_deadline", "action_pending"]:
        result.erase(key)
    return result

func status(id: String) -> Dictionary:
    poll()
    if not runs.has(id) and id != "" and id == id.get_file() and not id.begins_with(".") and not id.contains("\\") and not id.contains(":"):
        var path = _test_root().path_join(id)
        var prior = _read_data(path.path_join("outcome.json"))
        if prior.get("state") == "exited" and prior.get("run_id") == id:
            prior.path = path
            var child = _read_data(path.path_join("status.json"))
            if child.has("session_id"):
                prior.session_id = child.session_id
                prior.session_path = _test_root().path_join("runtime").path_join(str(child.session_id))
            runs[id] = prior
            while runs.size() > MAX_RUNS:
                runs.erase(runs.keys()[0])
    return _public(runs[id]) if runs.has(id) else {"ok": false, "error": "Unknown test run."}

func request_stop(id: String) -> Dictionary:
    if not runs.has(id):
        return {"ok": false, "error": "Unknown test run."}
    var run: Dictionary = runs[id]
    poll()
    if run.state == "exited" or run.stop_deadline > 0:
        return _public(run)
    if not JsonStore.write_dict(run.path.path_join("stop.json"), {"stop": true}):
        run.stop_reason = "Could not send graceful shutdown request."
    run.stop_method = "requested"
    run.stop_deadline = Time.get_ticks_msec() + grace_ms
    return _public(run)

func stop_all() -> void:
    for id in runs:
        request_stop(id)

func request_action(id: String, args: Dictionary) -> Dictionary:
    if not runs.has(id) or status(id).state != "running":
        return {"ok": false, "error": "Test game is not running."}
    var run: Dictionary = runs[id]
    if run.action_pending:
        return {"ok": false, "error": "A test action is already pending."}
    run.erase("action_result")
    DirAccess.remove_absolute(run.path.path_join("action-result.json"))
    if not JsonStore.write_dict(run.path.path_join("action.json"), args):
        return {"ok": false, "error": "Could not send test action."}
    run.action_pending = true
    return {"ok": true, "run_id": id, "pending": true}

func read_log(id: String, options: Dictionary = {}) -> Dictionary:
    if id == "":
        var history: Array[Dictionary] = []
        var dir = DirAccess.open(_test_root())
        if dir != null:
            var entries = dir.get_directories()
            entries.sort()
            entries.reverse()
            for entry in entries:
                if dir.is_link(entry) or entry == "runtime":
                    continue
                var outcome = _read_data(_test_root().path_join(entry).path_join("outcome.json"))
                history.append({"run_id": entry, "state": outcome.get("state", "unknown"), "mode": outcome.get("mode", "unknown"), "stop_method": outcome.get("stop_method", "")})
                if history.size() == MAX_RUNS:
                    break
        return {"ok": true, "rendered_allowed": rendered_allowed(), "runs": history}
    var result = status(id)
    if not result.ok:
        return result
    result.erase("action_result")
    result.rendered_allowed = rendered_allowed()
    if result.has("session_path"):
        var meta = _read_data(result.session_path.path_join("session.json"))
        if not meta.is_empty():
            var records = Reader.read_segments(result.session_path.get_base_dir(), result.session_id, meta, options)
            var formatted = Reader.format_response(records.records, meta, [], records.read_errors, options).response
            result.merge(formatted, true)
    # Raw tails include failures before Logger installation and shutdown failures.
    for channel in ["engine", "stdio", "stderr"]:
        var f = FileAccess.open(result.path.path_join(channel + ".log"), FileAccess.READ)
        if f != null:
            f.seek(maxi(0, f.get_length() - 2000))
            result[channel + "_tail"] = f.get_buffer(2000).get_string_from_utf8()
    return result

func _exit_tree() -> void:
    # Host teardown cannot wait for callbacks. Normal Stop uses the grace period.
    for run in runs.values():
        if run.state != "exited" and OS.is_process_running(run.pid):
            var error = OS.kill(run.pid)
            if error == OK:
                run.state = "exited"
            run.stop_method = "forced"
            run.stop_reason = "Host closed before the test completed."
            _save_outcome(run)
