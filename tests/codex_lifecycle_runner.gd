extends SceneTree
var failures := 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func wait_idle() -> void:
    while app.agent.busy: await process_frame

func wait_reload() -> void:
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame

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
    OS.set_environment("GAMESMITH_CODEX_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-codex.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Codex lifecycle"
    app.harness_option.select(3)
    app._create_game()
    app.agent.send_player_request("reload")
    await wait_reload()
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Codex reload waits for player approval")
    check(not app.runner.has_active_game(), "pending Codex reload does not execute game code")
    app.agent.approve_reload()
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "approved Codex reload finishes the request")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("codex")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    var native_session = JsonStore.read_dict(directory.path_join("session.json"), {}).get("session", "")
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "Codex bridge starts, inspects and stops a headless test")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend.get("pid"), "consecutive Codex turns reuse the backend")
    check(app.agent.last_context_tokens == 5120, "Codex reports last context usage rather than lifetime tokens")
    app.agent.send_player_request("reload")
    await wait_reload()
    var adapter_pid = app.agent.rpc.pid
    app.agent.cancel()
    await wait_idle()
    check(app.agent.pending_reload.is_empty() and not app.agent.busy, "Codex Stop clears pending approval and finishes")
    check(OS.is_process_running(adapter_pid), "healthy Codex Stop keeps the adapter")
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "", "Codex follow-up works after Stop")
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "" and JsonStore.read_dict(directory.path_join("session.json"), {}).get("session") == native_session, "Codex restart resumes the game's native thread")
    app.agent.send_player_request("provider-error")
    await wait_idle()
    check(app.agent.last_error == "Fixture provider error", "Codex native provider failure ends as failure")
    for mode in ["START", "STOP", "SETTLE"]:
        var flag = "GAMESMITH_CODEX_STUCK_" + mode
        OS.set_environment(flag, "1")
        app.agent.restart_runtime()
        app.agent.send_player_request("wait")
        await create_timer(0.6).timeout
        var stuck_pid = app.agent.rpc.pid
        var cli_pid = JsonStore.read_dict(app.tools.workspace.path_join(".codex-fixture-pids.json"), {}).get("cli", -1)
        var began = Time.get_ticks_msec()
        app.agent.cancel()
        while app.agent.busy and Time.get_ticks_msec() - began < 7000: await process_frame
        await create_timer(0.2).timeout
        check(not app.agent.busy and Time.get_ticks_msec() - began < 6500, "Codex Stop bounds stalled " + mode)
        check(not OS.is_process_running(stuck_pid) and not process_alive(int(cli_pid)), "Codex Stop kills adapter and backend for " + mode)
        OS.unset_environment(flag)
        if app.agent.busy:
            app.agent.restart_runtime()
            app.agent.busy = false
        app.agent.send_player_request("follow up")
        await wait_idle()
        check(app.agent.last_error == "", "Codex resumes after forced Stop " + mode)
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_CODEX_BIN")
    quit(1 if failures else 0)
