extends SceneTree

var failures = 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value:
        failures += 1

func wait_idle() -> void:
    while app.agent.busy:
        await process_frame

func process_alive(pid: int) -> bool:
    if OS.get_name() != "Windows":
        return OS.is_process_running(pid)
    var output: Array = []
    OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], output, true)
    return not output.is_empty() and ('"%d"' % pid) in str(output[0])

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "OpenCode native Stop"
    app.harness_option.select(2)
    app._create_game()
    app.agent.send_player_request("Write a minimal main.gd extending Node with variable stop_marker = 83. Test it with gamesmith_start_test_game headless, read its log and stop it, then call gamesmith_reload_game and wait for approval. Finish only after approval. Use native write and GameSmith tools.")
    while app.agent.busy and app.agent.pending_reload.is_empty():
        await process_frame
    check(not app.agent.pending_reload.is_empty(), "installed OpenCode reaches reload approval before Stop")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("opencode")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    var session = JsonStore.read_dict(directory.path_join("session.json"), {}).get("session")
    var pid = int(backend.get("pid", -1))
    app.agent.cancel()
    app.agent.send_player_request("THIS_REQUEST_MUST_NOT_START_WHILE_STOP_IS_PENDING")
    await wait_idle()
    check(process_alive(pid), "native Stop retains the installed OpenCode server")
    check(app.agent.pending_reload.is_empty() and not app.runner.has_active_game(), "Stop clears approval without reloading")
    app.agent.send_player_request("What was stop_marker in our conversation? Do not use tools. Answer STOP_RESUMED_83 if it was 83. Do not reload.")
    await wait_idle()
    check(app.agent.last_error == "" and "STOP_RESUMED_83" in app.agent.result_text, "same-session request completes after native cancellation")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == pid, "new message uses the same installed backend")
    check(JsonStore.read_dict(directory.path_join("session.json"), {}).get("session") == session, "native conversation survives Stop")
    app.queue_free()
    await process_frame
    check(not process_alive(pid), "closing GameSmith removes the installed backend process tree")
    quit(1 if failures else 0)
