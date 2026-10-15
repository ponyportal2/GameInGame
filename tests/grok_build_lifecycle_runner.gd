extends SceneTree
var failures := 0
var app
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1
func idle() -> void:
    # Isolate native lifecycle failures; shared recovery has its own matrix.
    app.agent.recovery_delays = []
    while app.agent.busy: await process_frame
func reload_pending() -> void:
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
func run() -> void:
    OS.set_environment("GAMESMITH_GROK_BUILD_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-grok-build.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Grok Build lifecycle"
    app.harness_option.select(6)
    app._create_game()
    app.agent.send_player_request("reload")
    await reload_pending()
    check(not app.agent.pending_reload.is_empty(), "Grok Build reload reaches host approval")
    check(not app.runner.has_active_game(), "Grok Build pending approval does not execute game code")
    app.agent.approve_reload()
    var consumed_token = app.agent.reload_grant
    check(not app.runner.has_active_game(), "ACP approval grants permission before MCP executes reload")
    await idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "Grok Build approved reload completes")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("grok-build")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    var session_file = directory.path_join("session.json")
    var session = JsonStore.read_dict(session_file, {}).get("session")
    var loaded_game = app.runner.active_game
    app.agent.send_player_request("wait")
    await create_timer(0.15).timeout
    for token in ["", consumed_token]:
        var replay = {"id": "replayed-approval", "command": "reload_game", "args": {"approval_token": token}}
        JsonStore.write_dict(app.agent.bridge_dir.path_join("request-replayed-approval.json"), replay)
        app.agent._service_host_bridge()
        var rejected = JsonStore.read_dict(app.agent.bridge_dir.path_join("response-replayed-approval.json"), {})
        check(app.agent.busy and not rejected.get("ok", true) and app.runner.active_game == loaded_game, "Grok Build rejects missing or consumed grants during an active turn")
    app.agent.cancel()
    await idle()
    check(app.agent.rpc == null, "Grok Build Stop retires the cancelled MCP queue")
    app.agent.send_player_request("test")
    await idle()
    check(app.agent.last_error == "", "Grok Build MCP starts, inspects and stops a headless game")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend.get("pid"), "Grok Build resumes in a clean backend after Stop")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    app.agent.send_player_request("policy")
    await idle()
    check(app.agent.last_error == "", "Grok Build denies native shell and workspace escapes")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend.get("pid"), "Grok Build ordinary turns reuse the backend")
    app.agent.send_player_request("reload")
    await reload_pending()
    app.agent.cancel()
    await idle()
    check(app.agent.pending_reload.is_empty(), "Grok Build Stop clears pending approval")
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "", "Grok Build accepts follow-up after native Stop")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend.get("pid"), "Grok Build Stop replaces its backend and resumes history")
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "" and JsonStore.read_dict(session_file, {}).get("session") == session, "Grok Build restarts resume the explicit game session")
    for phase in ["initialize", "session/load"]:
        OS.set_environment("GAMESMITH_GROK_BUILD_FAIL_METHOD", phase)
        app.agent.restart_runtime()
        app.agent.send_player_request("follow up")
        await idle()
        check("Fixture readiness failure" in app.agent.last_error and app.agent.rpc == null, "Grok Build failed readiness retires adapter: " + phase)
        OS.unset_environment("GAMESMITH_GROK_BUILD_FAIL_METHOD")
        app.agent.send_player_request("follow up")
        await idle()
        check(app.agent.last_error == "", "Grok Build readiness recovers on the next message")
    JsonStore.write_dict(session_file, {"session": "missing-native-session"})
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await idle()
    check("Start a new Grok Build session" in app.agent.last_error and JsonStore.read_dict(session_file, {}).get("session") == "missing-native-session", "Grok Build failed resume preserves history and explains recovery")
    app._open_settings()
    app.codex_new_session_button.pressed.emit()
    check(app.codex_session_dialog.visible and app.native_session_title.text == "Start a new Grok Build session?", "Grok Build session reset asks for confirmation")
    app._cancel_new_codex_session()
    check(JsonStore.read_dict(session_file, {}).get("session") == "missing-native-session", "cancelled Grok Build reset preserves reference")
    app._request_new_codex_session()
    app._confirm_new_codex_session()
    check(not FileAccess.file_exists(session_file), "confirmed Grok Build reset archives session reference")
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "", "fresh Grok Build session works after reset")
    var settings = app.metadata.global_settings()
    settings.auto_approve_reloads = true
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("reload")
    await idle()
    check(app.agent.last_error == "" and app.agent.pending_reload.is_empty(), "Grok Build automatic reload approval completes through ACP and MCP")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    for flag in ["GAMESMITH_GROK_BUILD_STUCK_START", "GAMESMITH_GROK_BUILD_STUCK_TURN", "GAMESMITH_GROK_BUILD_STUCK_CANCEL"]:
        OS.set_environment(flag, "1")
        app.agent.restart_runtime()
        app.agent.send_player_request("wait")
        await create_timer(0.7).timeout
        var start = Time.get_ticks_msec()
        app.agent.cancel()
        await idle()
        check(Time.get_ticks_msec() - start < 8000 and app.agent.rpc == null, "Grok Build Stop force-retires a stuck backend: " + flag)
        OS.unset_environment(flag)
        app.agent.send_player_request("follow up")
        await idle()
        check(app.agent.last_error == "", "Grok Build resumes after forced Stop")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
