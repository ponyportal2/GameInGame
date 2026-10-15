extends Node

var runs: Dictionary = {}
var runtime := ""

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func _prepare() -> bool:
    if runtime != "": return true
    var directory = ProjectSettings.globalize_path("user://host/blender-runtime")
    for pair in [["jobs.mjs", "blender/jobs.mjs"], ["bootstrap.py", "blender/bootstrap.py"], ["workspace-paths.mjs", "pi/workspace-paths.mjs"], ["process-tree.mjs", "agent/process-tree.mjs"]]:
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
        var pipe = OS.execute_with_pipe("node", PackedStringArray([runtime.path_join("jobs.mjs"), directory.path_join("config.json")]), false)
        if pipe.is_empty(): return {"ok": false, "error": "Could not start Blender supervisor. Install Node.js on PATH."}
        runs[id] = {"directory": directory, "pipe": pipe, "pid": pipe.pid}
        for old in runs.keys():
            if runs.size() <= 16: break
            if old != id and not OS.is_process_running(runs[old].pid): runs.erase(old)
        return {"ok": true, "run_id": id, "state": "starting"}
    var id = str(args.get("run_id", ""))
    if not runs.has(id): return {"ok": false, "error": "Unknown Blender run_id in this game window."}
    if action == "stop":
        _stop(runs[id])
    elif action != "status":
        return {"ok": false, "error": "Unknown Blender action. Use guide, start, status, stop or inspect."}
    return _status(id)

func _status(id: String) -> Dictionary:
    var run: Dictionary = runs[id]
    var result = JsonStore.read_dict(run.directory.path_join("status.json"), {"ok": true, "run_id": id, "state": "starting"})
    if not OS.is_process_running(run.pid):
        run.pipe.clear()
        if result.get("state") in ["starting", "running"]:
            result.merge({"ok": false, "state": "failed", "error": "Blender supervisor exited before reporting completion."}, true)
    return result

func has_running() -> bool:
    for id in runs:
        if OS.is_process_running(runs[id].pid): return true
    return false

func _stop(run: Dictionary) -> void:
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
