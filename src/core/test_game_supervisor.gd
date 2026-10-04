extends Node

# The host supervises liveness; no stop operation depends on a responsive child.
const Reader = preload("res://src/core/runtime_log_reader.gd")
const MAX_RUNS = 16
const RAW_CAPTURE_BYTES = 2 * 1024 * 1024
const Evidence = preload("res://src/core/test_evidence.gd")
var grace_ms := 5000
var parent_grace_ms := 15000
var run_budget_bytes := 32 * 1024 * 1024
var heartbeat_enabled := true
var last_heartbeat_ms := 0
var last_retention_ms := 0
var retention: Dictionary = {}
var runs: Dictionary = {}
var workspace_path := ""

func rebind(workspace: String) -> void:
    var old_root = _test_root()
    workspace_path = workspace
    var new_root = _test_root()
    Evidence.recover(new_root)
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
        if run.state not in ["exited", "interrupted"]:
            return true
    return false

func start(workspace: String, mode: String = "headless") -> Dictionary:
    if workspace_path != workspace:
        if has_running():
            return {"ok": false, "error": "Stop the existing test before changing games."}
        workspace_path = workspace
        Evidence.recover(_test_root())
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
    var token = Crypto.new().generate_random_bytes(16).hex_encode()
    var config = {"run_id": id, "workspace": source, "game": workspace.get_file(), "mode": mode, "control_dir": path, "diagnostics_root": path.get_base_dir().path_join("runtime"), "parent_pid": OS.get_process_id(), "parent_token": token, "parent_grace_ms": parent_grace_ms, "run_budget_bytes": run_budget_bytes}
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
    # The independent watchdog enforces the total run budget, including engine
    # logging and user data, even if generated code freezes the main thread.
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
    var run = {"ok": true, "run_id": id, "mode": mode, "pid": pipe.pid, "parent_token": token, "state": "starting", "path": path, "pipe": pipe, "stop_method": "", "stop_reason": "", "stop_deadline": 0, "action_pending": false, "rendered_allowed": rendered_allowed(), "raw_capture_limit_bytes": RAW_CAPTURE_BYTES}
    runs[id] = run
    _heartbeat(run)
    _save_outcome(run)
    _prune_runs()
    return _public(run)

func _process(_delta: float) -> void:
    poll()

func poll() -> void:
    var heartbeat_due = Time.get_ticks_msec() - last_heartbeat_ms >= 1000
    if heartbeat_due:
        last_heartbeat_ms = Time.get_ticks_msec()
    for run in runs.values():
        if run.state in ["exited", "interrupted"]:
            continue
        if heartbeat_due:
            _heartbeat(run)
        for channel in ["stdio", "stderr"]:
            var stream: FileAccess = run.pipe.get(channel)
            if stream != null:
                # Bounded work each frame, and explicit raw-output loss counts.
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
            if not action.is_empty() and action.get("action_id") == run.get("action_id"):
                run.action_result = action
                run.action_pending = false
        if not OS.is_process_running(run.pid):
            run.state = "exited"
            run.exit_code = OS.get_process_exit_code(run.pid)
            if run.stop_method == "requested":
                run.stop_method = "graceful" if child.get("graceful_exit", false) else "unconfirmed"
            var watchdog = _read_data(run.path.path_join("watchdog.json"))
            if not watchdog.is_empty():
                run.stop_method = "graceful" if child.get("graceful_exit", false) else "forced"
                run.stop_reason = "Watchdog stopped test: " + str(watchdog.reason)
            run.pipe.clear()
            _save_outcome(run)
        elif run.stop_deadline > 0 and Time.get_ticks_msec() >= run.stop_deadline:
            var error = OS.kill(run.pid)
            run.stop_method = "forced" if error == OK else "kill_failed"
            run.stop_reason = "Process did not exit after the graceful shutdown request; it may be hung or its control channel may have failed."
            run.stop_deadline = 0 if error == OK else Time.get_ticks_msec() + grace_ms
            _save_outcome(run)

    if workspace_path != "" and Time.get_ticks_msec() - last_retention_ms > 5000:
        last_retention_ms = Time.get_ticks_msec()
        var active: Array = []
        for run in runs.values():
            if run.state not in ["exited", "interrupted"]:
                active.append(run.run_id)
        retention = Evidence.enforce(_test_root(), active)

func _heartbeat(run: Dictionary) -> void:
    if not heartbeat_enabled:
        return
    var file = FileAccess.open(run.path.path_join("parent-heartbeat"), FileAccess.WRITE)
    if file != null:
        file.store_string(str(run.parent_token) + ":" + str(Time.get_unix_time_from_system()))

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
    var index = _read_data(_test_root().path_join("retention.json"))
    for expired in index.get("expired", []):
        if expired.get("run_id") == id:
            return {"ok": false, "error": "retention_expired", "retention": expired}
    if (not runs.has(id) or runs[id].state == "interrupted") and id != "" and id == id.get_file() and not id.begins_with(".") and not id.contains("\\") and not id.contains(":"):
        Evidence.recover(_test_root())
        var path = _test_root().path_join(id)
        var prior = _read_data(path.path_join("outcome.json"))
        if prior.get("state") in ["exited", "interrupted"] and prior.get("run_id") == id:
            prior.path = path
            var child = _read_data(path.path_join("status.json"))
            if child.has("session_id"):
                prior.session_id = child.session_id
                prior.session_path = _test_root().path_join("runtime").path_join(str(child.session_id))
            runs[id] = prior
            _prune_runs(id)
    if runs.has(id) and not DirAccess.dir_exists_absolute(runs[id].path):
        return {"ok": false, "error": "retention_expired", "run_id": id}
    return _public(runs[id]) if runs.has(id) else {"ok": false, "error": "Unknown test run."}

func request_stop(id: String) -> Dictionary:
    if not runs.has(id):
        return {"ok": false, "error": "Unknown test run."}
    var run: Dictionary = runs[id]
    poll()
    if run.state == "interrupted":
        return {"ok": false, "error": "Test owner was lost; its watchdog handles cleanup. A recovered PID is never killed blindly."}
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
    if args.get("action") == "poll":
        var state = status(id)
        if not state.get("ok", false):
            return state
        if args.get("action_id", "") != state.get("action_id", ""):
            return {"ok": false, "error": "Unknown or superseded test action."}
        if state.has("action_result"):
            return state.action_result
        if state.state in ["exited", "interrupted"]:
            return {"ok": false, "error": "Test process ended or ownership was lost before completing the action.", "process": state}
        return {"ok": true, "run_id": id, "action_id": state.action_id, "pending": true}
    if not runs.has(id) or status(id).state != "running":
        return {"ok": false, "error": "Test game is not running."}
    var run: Dictionary = runs[id]
    if run.action_pending:
        return {"ok": false, "error": "A test action is already pending."}
    run.erase("action_result")
    DirAccess.remove_absolute(run.path.path_join("action-result.json"))
    var action_id = Crypto.new().generate_random_bytes(8).hex_encode()
    var request = args.duplicate(true)
    request.action_id = action_id
    if not JsonStore.write_dict(run.path.path_join("action.json"), request):
        return {"ok": false, "error": "Could not send test action."}
    run.action_pending = true
    run.action_id = action_id
    return {"ok": true, "run_id": id, "action_id": action_id, "pending": true}

func read_log(id: String, options: Dictionary = {}) -> Dictionary:
    if id == "":
        Evidence.recover(_test_root())
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
        return {"ok": true, "rendered_allowed": rendered_allowed(), "runs": history, "retention": _read_data(_test_root().path_join("retention.json"))}
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
        if run.state not in ["exited", "interrupted"] and OS.is_process_running(run.pid):
            var error = OS.kill(run.pid)
            if error == OK:
                run.state = "exited"
            run.stop_method = "forced"
            run.stop_reason = "Host closed before the test completed."
            _save_outcome(run)

func _prune_runs(keep: String = "") -> void:
    for id in runs.keys():
        if runs.size() <= MAX_RUNS:
            break
        if id != keep and runs[id].state in ["exited", "interrupted"]:
            runs.erase(id)
