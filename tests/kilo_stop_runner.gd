extends SceneTree
var failures := 0
func _init() -> void:
    call_deferred("run")
func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value: failures += 1
func process_alive(pid: int) -> bool:
    if pid <= 0: return false
    var output: Array = []
    if OS.get_name() != "Windows":
        var code = OS.execute("ps", ["-p", str(pid), "-o", "stat="], output)
        var state = str(output[0]).strip_edges() if not output.is_empty() else ""
        return code == 0 and state != "" and not state.begins_with("Z")
    OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], output, true)
    return not output.is_empty() and ('"%d"' % pid) in str(output[0])
func run() -> void:
    OS.set_environment("GAMESMITH_KILO_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-kilo.mjs"))
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Stalled cancellation"
    app.harness_option.select(10)
    app._create_game()
    for mode in ["START", "ABORT", "SETTLE"]:
        app.agent.restart_runtime()
        var flag = "GAMESMITH_FIXTURE_STUCK_" + mode
        OS.set_environment(flag, "1")
        app.agent.send_player_request("settle-stall" if mode == "SETTLE" else "stuck-abort")
        await create_timer(0.6).timeout
        var old_pid = app.agent.rpc.pid
        var children = JsonStore.read_dict(app.tools.workspace.path_join(".kilo-fixture-pids.json"), {})
        var started = Time.get_ticks_msec()
        app.agent.cancel()
        while app.agent.busy and Time.get_ticks_msec() - started < 7000:
            await process_frame
        # SIGKILL delivery is asynchronous; allow descendants to leave the CPU.
        await create_timer(0.2).timeout
        check(not app.agent.busy, "Stop settles stalled " + mode)
        check(Time.get_ticks_msec() - started < 6500, "Stop grace bounds " + mode)
        check(not OS.is_process_running(old_pid), "Stop kills blocked adapter " + mode)
        check(not children.is_empty() and not process_alive(int(children.get("cli", -1))) and not process_alive(int(children.get("mcp", -1))), "forced Stop kills backend and MCP " + mode)
        OS.unset_environment(flag)
        if app.agent.busy:
            app.agent.restart_runtime()
            app.agent.busy = false
        app.agent.send_player_request("follow up")
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "", "request resumes after forced Stop " + mode)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
