extends SceneTree
var failures := 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value:
        failures += 1

func wait_idle() -> void:
    while app.agent.busy:
        await process_frame

func wait_reload() -> void:
    while app.agent.busy and app.agent.pending_reload.is_empty():
        await process_frame

func process_alive(pid: int) -> bool:
    var output: Array = []
    if OS.get_name() != "Windows":
        var code = OS.execute("ps", ["-p", str(pid), "-o", "stat="], output)
        var state = str(output[0]).strip_edges() if not output.is_empty() else ""
        return code == 0 and state != "" and not state.begins_with("Z")
    OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], output, true)
    return not output.is_empty() and ('"%d"' % pid) in str(output[0])

func run() -> void:
    OS.set_environment("GAMESMITH_KILO_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-kilo.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Kilo lifecycle"
    app.harness_option.select(10)
    app._create_game()
    app.rename_target = app.current_game
    app.rename_edit.text = "Kilo lifecycle renamed before session"
    app._rename_game()
    check(app.current_game == "Kilo lifecycle renamed before session", "Kilo game can be renamed before its first native session")
    app.agent.send_player_request("reload")
    await wait_reload()
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Kilo reload waits for approval")
    if app.agent.pending_reload.is_empty():
        print("Kilo initialization failure: " + app.agent.last_error)
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(not app.runner.has_active_game(), "pending reload does not execute game code")
    app.agent.approve_reload()
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "approved reload finishes the Kilo request")
    var backend_before = JsonStore.read_dict(app.metadata.game_meta_dir(app.current_game).path_join("kilo/backend.json"), {})
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "Kilo bridge starts and gracefully stops a test")
    check(not backend_before.is_empty() and JsonStore.read_dict(app.metadata.game_meta_dir(app.current_game).path_join("kilo/backend.json"), {}).get("pid") == backend_before.get("pid"), "consecutive messages reuse one Kilo backend")
    app.agent.send_player_request("reload")
    await wait_reload()
    var old_pid = app.agent.rpc.pid
    var child_pids = JsonStore.read_dict(app.tools.workspace.path_join(".kilo-fixture-pids.json"), {})
    app.agent.cancel()
    await wait_idle()
    check(not app.agent.busy and app.agent.pending_reload.is_empty(), "Stop cancels Kilo and pending reload")
    check(OS.is_process_running(old_pid), "native Stop retains the adapter for the next request")
    check(process_alive(int(child_pids.get("cli", -1))) and process_alive(int(child_pids.get("mcp", -1))), "native Stop retains the backend and MCP connection")
    var session_file = app.metadata.game_meta_dir(app.current_game).path_join("kilo/session.json")
    var saved_session = JsonStore.read_dict(session_file, {}).get("session", "")
    var rename = app.store.rename_game(app.current_game, "Moved Kilo lifecycle")
    check(not rename.get("ok", true) and "Kilo" in rename.get("error", ""), "rename protects Kilo's native workspace binding")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.tools.workspace)) and JsonStore.read_dict(session_file, {}).get("session") == saved_session, "rejected rename preserves workspace and native history")
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "", "a new request works after cancellation")
    check(saved_session != "" and JsonStore.read_dict(session_file, {}).get("session") == saved_session, "Kilo resumes the same native session after Stop")
    app.agent.send_player_request("provider-error")
    await wait_idle()
    check(app.agent.last_error == "Fixture provider error", "native Kilo provider errors finish the request as failures")
    app.agent.send_player_request("incomplete")
    await wait_idle()
    check(app.agent.last_error != "", "an incomplete Kilo subprocess cannot report success")
    app.agent.send_player_request("tool-round-only")
    await wait_idle()
    check(app.agent.last_error != "", "a subprocess ending after a tool round cannot report success")
    var settings = app.metadata.global_settings()
    settings.auto_approve_reloads = true
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("repair-reload")
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.active_game.get("repaired") == true, "failed reload diagnostics let Kilo repair, test and reload in the same request")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_KILO_BIN")
    quit(1 if failures else 0)
