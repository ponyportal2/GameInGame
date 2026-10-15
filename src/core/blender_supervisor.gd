extends Node

signal approval_changed(review: Dictionary)

var runs: Dictionary = {}
var runtime := ""
var recovery_elapsed := 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
    recovery_elapsed += delta
    if recovery_elapsed < 0.5: return
    recovery_elapsed = 0.0
    for id in runs: _status(id)

func _prepare() -> bool:
    if runtime != "": return true
    var directory = ProjectSettings.globalize_path("user://host/blender-runtime")
    for pair in [["jobs.mjs", "blender/jobs.mjs"], ["ownership.mjs", "blender/ownership.mjs"], ["bootstrap.py", "blender/bootstrap.py"], ["workspace-paths.mjs", "pi/workspace-paths.mjs"], ["process-tree.mjs", "agent/process-tree.mjs"]]:
        if not JsonStore.write_bytes_atomic(directory.path_join(pair[0]), FileAccess.get_file_as_bytes("res://tools/" + pair[1])):
            return false
    runtime = directory
    return true

func execute(workspace: String, args: Dictionary) -> Dictionary:
    var action = str(args.get("action", "guide"))
    if action == "guide":
        return {"ok": true, "instructions": FileAccess.get_file_as_string("res://tools/blender/guide.md")}
    if not _prepare(): return {"ok": false, "error": "Could not prepare the Blender runtime."}
    if action == "inspect":
        var output: Array = []
        var code = OS.execute("node", PackedStringArray([runtime.path_join("jobs.mjs"), "--inspect", ProjectSettings.globalize_path(workspace), str(args.get("path", ""))]), output, false, false)
        var result = JSON.parse_string("".join(output))
        if not result is Dictionary:
            return {"ok": false, "error": "Could not inspect PNG with Node.js (exit %d)." % code}
        if result.get("ok", false):
            var image = Image.new()
            if image.load_png_from_buffer(Marshalls.base64_to_raw(result.image_base64)) != OK:
                return {"ok": false, "error": "The preview PNG could not be decoded."}
        return result
    if action == "start":
        if has_running(): return {"ok": false, "error": "Stop the current Blender job or wait for it to finish."}
        var id = Crypto.new().generate_random_bytes(12).hex_encode()
        var directory = ProjectSettings.globalize_path("user://host/games".path_join(workspace.get_file()).path_join("blender").path_join(id))
        var config = {"workspace": ProjectSettings.globalize_path(workspace), "run_id": id, "directory": directory, "parent_pid": OS.get_process_id()}
        for key in ["script", "blend", "render"]:
            if args.has(key): config[key] = args[key]
        if not JsonStore.write_dict(directory.path_join("config.json"), config):
            return {"ok": false, "error": "Could not write Blender job configuration."}
        runs[id] = {"directory": directory, "pipe": {}, "pid": -1}
        for old in runs.keys():
            if runs.size() <= 16: break
            if old != id and _status(old).get("state") not in ["starting", "running", "awaiting_approval"]: runs.erase(old)
        if args.get("script", "") != "":
            var review = _command("--review", directory.path_join("config.json"))
            if not review.get("ok", false):
                runs.erase(id)
                return review
            config.script_sha256 = review.sha256
            if not JsonStore.write_dict(directory.path_join("config.json"), config):
                runs.erase(id)
                return {"ok": false, "error": "Could not save reviewed Blender script."}
            runs[id].pending = {"ok": true, "run_id": id, "state": "awaiting_approval"}
            if bool(MetadataStore.new().global_settings().get("auto_approve_blender_scripts", false)):
                return _launch(id)
            review.run_id = id
            approval_changed.emit(review)
            return _status(id)
        return _launch(id)
    var id = str(args.get("run_id", ""))
    if not runs.has(id): return {"ok": false, "error": "Unknown Blender run_id in this game window."}
    if action == "stop":
        _stop(runs[id])
    elif action != "status":
        return {"ok": false, "error": "Unknown Blender action. Use guide, start, status, stop or inspect."}
    return _status(id)

func _command(action: String, config: String) -> Dictionary:
    var output: Array = []
    var code = OS.execute("node", PackedStringArray([runtime.path_join("jobs.mjs"), action, config]), output, false, false)
    var result = JSON.parse_string("".join(output))
    return result if result is Dictionary else {"ok": false, "error": "Blender helper failed (exit %d)." % code}

func _launch(id: String) -> Dictionary:
    var run: Dictionary = runs[id]
    var pipe = OS.execute_with_pipe("node", PackedStringArray([runtime.path_join("jobs.mjs"), run.directory.path_join("config.json")]), false)
    var result: Dictionary
    if pipe.is_empty():
        result = {"ok": false, "run_id": id, "state": "failed", "error": "Could not start Blender supervisor. Install Node.js on PATH."}
        run.pending = result
    else:
        run.erase("pending")
        run.pipe = pipe
        run.pid = pipe.pid
        result = {"ok": true, "run_id": id, "state": "starting"}
    return result

# Called by the player UI; automatic approval is host-owned above.
func approve(id: String) -> Dictionary:
    if not runs.has(id) or runs[id].get("pending", {}).get("state") != "awaiting_approval":
        return {"ok": false, "error": "This Blender approval is no longer pending."}
    var result = _launch(id)
    approval_changed.emit({})
    return result

func _status(id: String) -> Dictionary:
    var run: Dictionary = runs[id]
    if run.has("pending"): return run.pending
    if run.has("terminal"): return run.terminal
    var result = JsonStore.read_dict(run.directory.path_join("status.json"), {"ok": true, "run_id": id, "state": "starting"})
    if not OS.is_process_running(run.pid):
        run.pipe.clear()
        if result.get("state") in ["starting", "running"]:
            var cleanup = {"ok": true}
            if result.get("pid", 0) > 1:
                cleanup = _command("--cleanup", run.directory.path_join("config.json"))
            run.cleanup_failed = not cleanup.get("ok", false)
            result.merge({"ok": false, "state": "failed", "error": "Blender supervisor exited before reporting completion."}, true)
            if run.cleanup_failed:
                result.error += " Cleanup could not verify/terminate its child: " + str(cleanup.get("error", "unknown error"))
        run.terminal = result
    return result

func has_running() -> bool:
    for id in runs:
        var state: Dictionary = _status(id)
        if state.get("state") in ["starting", "running", "awaiting_approval"] or runs[id].get("cleanup_failed", false): return true
    return false

func _stop(run: Dictionary) -> void:
    if run.get("pending", {}).get("state") == "awaiting_approval":
        run.pending = {"ok": false, "run_id": run.pending.run_id, "state": "cancelled", "error": "Player declined or cancelled Blender Python execution."}
        approval_changed.emit({})
    if run.get("cleanup_failed", false):
        var cleanup = _command("--cleanup", run.directory.path_join("config.json"))
        run.cleanup_failed = not cleanup.get("ok", false)
    if OS.is_process_running(run.pid):
        JsonStore.write_bytes_atomic(run.directory.path_join("stop"), "stop".to_utf8_buffer())

func stop_all() -> void:
    for run in runs.values(): _stop(run)

func _exit_tree() -> void:
    stop_all()
    for run in runs.values():
        for key in ["stdio", "stderr"]:
            var stream: FileAccess = run.pipe.get(key)
            if stream != null: stream.close()
        run.pipe.clear()
