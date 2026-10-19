extends RefCounted

const Supervisor = preload("res://src/core/test_game_supervisor.gd")
const CODE_EXTENSIONS = ["gd", "gdshader", "gdshaderinc", "shader", "tscn", "tres", "scn", "res", "cs", "dll", "godot", "cfg"]

static func fingerprint(workspace: String) -> Dictionary:
    var result := {"ok": true, "files": {}, "bytes": 0}
    _collect(workspace, workspace, result)
    return result

static func _collect(path: String, root: String, result: Dictionary) -> void:
    var dir = DirAccess.open(path)
    if dir == null:
        result.ok = false
        return
    for file in dir.get_files():
        if file.get_extension().to_lower() not in CODE_EXTENSIONS: continue
        var full = path.path_join(file)
        var input = FileAccess.open(full, FileAccess.READ)
        if dir.is_link(file) or input == null:
            result.ok = false
            return
        result.bytes += input.get_length()
        input.close()
        if result.files.size() >= 10000 or result.bytes > 64 * 1024 * 1024:
            result.ok = false
            return
        var digest = FileAccess.get_sha256(full)
        if digest == "": result.ok = false
        result.files[full.trim_prefix(root + "/")] = digest
    for child in dir.get_directories():
        if child in [".git", ".godot"]: continue
        if dir.is_link(child):
            result.ok = false
            return
        _collect(path.path_join(child), root, result)
        if not result.ok: return

static func run(owner: Node, workspace: String, cancelled: Callable, timeout_ms: int, operation: Dictionary = {}) -> Dictionary:
    var supervisor = Supervisor.new()
    supervisor.storage_scope = "preflights"
    owner.add_child(supervisor)
    var started = supervisor.start(workspace)
    if not started.ok:
        supervisor.free()
        return {"ok": false, "reason": "launch_failed", "error": started.get("error", "Could not start preflight.")}
    # Poll results are owned by the supervisor; do not enrich that same object
    # with a status containing action_result (which would create a JSON cycle).
    var result: Dictionary = (await supervisor.run_smoke_window(started.run_id, cancelled, timeout_ms, operation)).duplicate(true)
    supervisor.request_stop(started.run_id)
    var cleanup_deadline = Time.get_ticks_msec() + supervisor.grace_ms + 3000
    while supervisor.status(started.run_id).get("state") != "exited" and Time.get_ticks_msec() < cleanup_deadline:
        await owner.get_tree().process_frame
    result.run_id = started.run_id
    result.cleanup = supervisor.status(started.run_id)
    result.cleanup.erase("action_result")
    result.diagnostics = supervisor.read_log(started.run_id, {"severity": "error", "limit": 10})
    if result.cleanup.get("state") != "exited" or result.cleanup.get("stop_method") != "graceful" or int(result.cleanup.get("exit_code", -1)) != 0:
        result.ok = false
        if result.get("reason") == "passed":
            result.reason = "cleanup_failed"
            result.error = "Preflight did not shut down cleanly."
    # Include errors raised by generated cleanup, not only the smoke window.
    if not result.diagnostics.get("records", []).is_empty() or not result.diagnostics.get("read_errors", []).is_empty():
        result.ok = false
        if result.get("reason") == "passed":
            result.reason = "cleanup_errors"
            result.error = "Preflight cleanup emitted errors or diagnostics could not be read."
    supervisor.free()
    return result
