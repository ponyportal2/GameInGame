extends SceneTree

const Supervisor = preload("res://src/core/test_game_supervisor.gd")
var failed := 0

class ExitRaceSupervisor:
    extends "res://src/core/test_game_supervisor.gd"
    var publish_exit := true

    func _read_data(path: String) -> Dictionary:
        var value = super._read_data(path)
        if publish_exit and path.get_file() == "status.json":
            publish_exit = false
            # Deterministically publish the child's final record immediately
            # after the parent's first read, before its liveness check.
            JsonStore.write_dict(path, {"state": "exited", "graceful_exit": true,
                "session_id": "final-session", "startup_smoke": {"ok": true}})
        return value

func check(value: bool, label: String) -> void:
    if not value: failed += 1
    print("PASS: " if value else "FAIL: ", label)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    # Use a real exited child PID, rather than relying on an invented identity.
    var child = OS.execute_with_pipe(OS.get_executable_path(), ["--headless", "--version"], false)
    if child.is_empty():
        check(false, "launch short-lived child")
        quit(1)
        return
    var deadline = Time.get_ticks_msec() + 10000
    while OS.is_process_running(child.pid) and Time.get_ticks_msec() < deadline:
        for channel in ["stdio", "stderr"]:
            if child.get(channel) != null:
                child[channel].get_buffer(4096)
        await process_frame
    if OS.is_process_running(child.pid):
        OS.kill(child.pid)
        check(false, "short-lived child exits")
        quit(1)
        return
    var child_pid: int = child.pid
    child.clear()
    for graceful in [true, false]:
        var supervisor = ExitRaceSupervisor.new() if graceful else Supervisor.new()
        supervisor.heartbeat_enabled = false
        supervisor.set_process(false)
        root.add_child(supervisor)
        var path = ProjectSettings.globalize_path("user://exit-race/" + str(graceful))
        JsonStore.write_dict(path.path_join("status.json"), {"state": "running"})
        var run_id = "exit-race"
        supervisor.runs[run_id] = {"ok": true, "run_id": run_id, "path": path,
            "pid": child_pid, "state": "running", "pipe": {},
            "action_pending": false, "stop_method": "requested", "stop_deadline": 0}
        supervisor.poll()
        var result: Dictionary = supervisor.runs[run_id]
        check(result.state == "exited", "Exited child is finalized")
        check(result.stop_method == ("graceful" if graceful else "unconfirmed"),
            "Final status is reread after exit; missing evidence stays unconfirmed")
        if graceful:
            check(result.get("session_id") == "final-session" and result.get("startup_smoke", {}).get("ok", false),
                "Final diagnostic and smoke fields are retained")
        var saved = JsonStore.read_dict(path.path_join("outcome.json"))
        check(saved.get("stop_method") == result.stop_method, "Persisted outcome agrees with final status")
        supervisor.free()
    quit(1 if failed else 0)
