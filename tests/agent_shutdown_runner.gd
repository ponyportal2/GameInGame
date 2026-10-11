extends SceneTree

func _init() -> void:
    call_deferred("run")

func process_alive(pid: int) -> bool:
    if OS.get_name() != "Windows":
        return OS.is_process_running(pid)
    var output: Array = []
    OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], output, true)
    return not output.is_empty() and ('"%d"' % pid) in str(output[0])

func run() -> void:
    var session = preload("res://src/agent/command_code_session.gd").new()
    root.add_child(session)
    var path = ProjectSettings.globalize_path("user://race-pids.json")
    session.start({"worker": ProjectSettings.globalize_path("res://tools/testing/fake-launcher-race.mjs"), "config_path": path})
    while not FileAccess.file_exists(path):
        await process_frame
    var pids = JSON.parse_string(FileAccess.get_file_as_string(path))
    session.shutdown()
    await create_timer(0.2).timeout
    var survived = process_alive(int(pids.child))
    if survived:
        OS.kill(int(pids.child))
        push_error("FAIL: pipe EOF must not orphan the agent child before the tree kill")
    else:
        print("PASS: shutdown kills the child tree before closing adapter pipes")
    quit(1 if survived else 0)
