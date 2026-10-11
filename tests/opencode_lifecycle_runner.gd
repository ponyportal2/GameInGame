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

func run() -> void:
    OS.set_environment("GAMESMITH_OPENCODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-opencode.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "OpenCode lifecycle"
    app.harness_option.select(2)
    app._create_game()
    app.agent.send_player_request("reload")
    await wait_reload()
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "OpenCode reload waits for approval")
    check(not app.runner.has_active_game(), "pending reload does not execute game code")
    app.agent.approve_reload()
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "approved reload finishes the OpenCode request")
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "OpenCode bridge starts and gracefully stops a test")
    app.agent.send_player_request("reload")
    await wait_reload()
    var old_pid = app.agent.rpc.pid
    var child_pids = JsonStore.read_dict(app.store.game_path(app.current_game).path_join(".opencode-fixture-pids.json"), {})
    app.agent.cancel()
    await process_frame
    check(not app.agent.busy and app.agent.pending_reload.is_empty(), "Stop cancels OpenCode and pending reload")
    check(not OS.is_process_running(old_pid), "Stop terminates the adapter process")
    check(not OS.is_process_running(int(child_pids.get("cli", -1))) and not OS.is_process_running(int(child_pids.get("mcp", -1))), "Stop terminates OpenCode and its MCP child")
    var session_file = app.metadata.game_meta_dir(app.current_game).path_join("opencode/session.json")
    var saved_session = JsonStore.read_dict(session_file, {}).get("session", "")
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "", "a new request works after cancellation")
    check(saved_session != "" and JsonStore.read_dict(session_file, {}).get("session") == saved_session, "OpenCode resumes the same native session after Stop")
    app.agent.send_player_request("provider-error")
    await wait_idle()
    check(app.agent.last_error == "Fixture provider error", "native OpenCode provider errors finish the request as failures")
    app.agent.send_player_request("incomplete")
    await wait_idle()
    check(app.agent.last_error != "", "an incomplete OpenCode subprocess cannot report success")
    app.agent.send_player_request("tool-round-only")
    await wait_idle()
    check(app.agent.last_error != "", "a subprocess ending after a tool round cannot report success")
    var settings = app.metadata.global_settings()
    settings.auto_approve_reloads = true
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("repair-reload")
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.active_game.get("repaired") == true, "failed reload diagnostics let OpenCode repair, test and reload in the same request")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_OPENCODE_BIN")
    quit(1 if failures else 0)
