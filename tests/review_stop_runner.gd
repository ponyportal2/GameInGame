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
func wait_for_file(path: String, timeout_ms: int) -> bool:
    var started = Time.get_ticks_msec()
    while Time.get_ticks_msec() - started < timeout_ms:
        if FileAccess.file_exists(path): return true
        await create_timer(0.05).timeout
    return false
func wait_dead_os(pid: int, timeout_ms: int) -> bool:
    if pid <= 0: return true
    var started = Time.get_ticks_msec()
    while OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
        await create_timer(0.05).timeout
    return not OS.is_process_running(pid)
func wait_dead(pid: int, timeout_ms: int) -> bool:
    if pid <= 0: return true
    var started = Time.get_ticks_msec()
    while process_alive(pid) and Time.get_ticks_msec() - started < timeout_ms:
        await create_timer(0.05).timeout
    return not process_alive(pid)
func run() -> void:
    OS.set_environment("GAMESMITH_OPENCODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-opencode.mjs"))
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Stalled cancellation"
    app.harness_option.select(2)
    app._create_game()
    for mode in ["START", "ABORT", "SETTLE"]:
        app.agent.restart_runtime()
        var flag = "GAMESMITH_FIXTURE_STUCK_" + mode
        OS.set_environment(flag, "1")
        var marker = app.tools.workspace.path_join(".opencode-fixture-busy.json")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
        app.agent.send_player_request("settle-stall" if mode == "SETTLE" else "stuck-abort")
        # Wait until the fixture actually starts the turn. A fixed delay can cancel
        # before the prompt is in flight, which leaves a healthy runtime alive and
        # makes this test flaky.
        await wait_for_file(marker, 5000)
        var old_pid = app.agent.rpc.pid
        var children = JsonStore.read_dict(app.tools.workspace.path_join(".opencode-fixture-pids.json"), {})
        var started = Time.get_ticks_msec()
        app.agent.cancel()
        while app.agent.busy and Time.get_ticks_msec() - started < 7000:
            await process_frame
        var settled_ms = Time.get_ticks_msec() - started
        check(not app.agent.busy, "Stop settles stalled " + mode)
        check(settled_ms < 6500, "Stop grace bounds " + mode)
        # Process termination is asynchronous; poll instead of assuming a fixed delay.
        var adapter_dead = await wait_dead_os(old_pid, 3000)
        var cli_dead = await wait_dead(int(children.get("cli", -1)), 3000)
        var mcp_dead = await wait_dead(int(children.get("mcp", -1)), 3000)
        check(adapter_dead, "Stop kills blocked adapter " + mode)
        check(not children.is_empty() and cli_dead and mcp_dead, "forced Stop kills backend and MCP " + mode)
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
