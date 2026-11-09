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
    OS.set_environment("GAMESMITH_CLAUDE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-claude.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Claude Code lifecycle"
    for item in app.harness_option.item_count:
        if str(app.harness_option.get_item_metadata(item)) == "claude": app.harness_option.select(item)
    app._create_game()
    app._open_settings()
    check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable and app.reasoning_option.disabled, "Claude Code owns native model, provider, credentials and reasoning")
    check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "Claude Code owns native compaction")
    var native_settings = app.metadata.global_settings()
    app.model_edit.text = "must not save"
    app.compaction_auto_spin.value = 999
    app.compaction_keep_spin.value = 999
    app._save_settings()
    var saved_settings = app.metadata.global_settings()
    for key in native_settings:
        check(saved_settings.get(key) == native_settings[key], "Claude Code preserves setting " + key)
    var other_session = app.metadata.game_meta_dir(app.current_game).path_join("codebuddy/session.json")
    check(JsonStore.write_dict(other_session, {"session": "other-provider-sentinel"}), "writes a different provider reference")
    var initial_settings = app.metadata.global_settings()
    initial_settings.auto_approve_reloads = false
    app.metadata.save_global_settings(initial_settings)
    app.agent.send_player_request("reload")
    await reload_pending()
    check(not app.agent.pending_reload.is_empty(), "Claude Code reload reaches host approval")
    check(not app.runner.has_active_game(), "Claude Code pending approval does not execute game code")
    app.agent.approve_reload()
    await idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "Claude Code approved reload completes")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("claude")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    var session_file = directory.path_join("session.json")
    var session = JsonStore.read_dict(session_file, {}).get("session")
    app.agent.send_player_request("wait")
    await create_timer(0.15).timeout
    check(not app.agent.start_new_session().get("ok", true), "busy Claude Code reset is rejected")
    app.agent.cancel()
    await idle()
    check(app.agent.rpc == null, "Claude Code Stop retires the cancelled MCP queue")
    app.agent.send_player_request("test")
    await idle()
    check(app.agent.last_error == "", "Claude Code MCP starts, inspects and stops a headless game")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend.get("pid"), "Claude Code resumes in a clean backend after Stop")
    await create_timer(0.05).timeout
    check(app.agent.last_context_tokens == 425, "Claude Code reports native current context after the final response")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    app.agent.send_player_request("policy")
    await idle()
    check(app.agent.last_error == "", "Claude Code bounded MCP rejects workspace escapes")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend.get("pid"), "Claude Code ordinary turns reuse the backend")
    app.agent.send_player_request("reload")
    await reload_pending()
    app.agent.cancel()
    await idle()
    check(app.agent.pending_reload.is_empty(), "Claude Code Stop clears pending approval")
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "", "Claude Code accepts follow-up after native Stop")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend.get("pid"), "Claude Code Stop replaces its backend and resumes history")
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "" and JsonStore.read_dict(session_file, {}).get("session") == session, "Claude Code restarts resume the explicit game session")
    for phase in ["initialize", "session/load"]:
        OS.set_environment("GAMESMITH_CLAUDE_FAIL_METHOD", phase)
        app.agent.restart_runtime()
        app.agent.send_player_request("follow up")
        await idle()
        check("Fixture readiness failure" in app.agent.last_error and app.agent.rpc == null, "Claude Code failed readiness retires adapter: " + phase)
        OS.unset_environment("GAMESMITH_CLAUDE_FAIL_METHOD")
        app.agent.send_player_request("follow up")
        await idle()
        check(app.agent.last_error == "", "Claude Code readiness recovers on the next message")
    JsonStore.write_dict(session_file, {"session": "missing-native-session"})
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await idle()
    check("Start a new Claude Code session" in app.agent.last_error and JsonStore.read_dict(session_file, {}).get("session") == "missing-native-session", "Claude Code failed resume preserves history and explains recovery")
    app._open_settings()
    app.codex_new_session_button.pressed.emit()
    check(app.codex_session_dialog.visible and app.native_session_title.text == "Start a new Claude Code session?", "Claude Code session reset asks for confirmation")
    app._cancel_new_codex_session()
    check(JsonStore.read_dict(session_file, {}).get("session") == "missing-native-session", "cancelled Claude Code reset preserves reference")
    app._request_new_codex_session()
    app._confirm_new_codex_session()
    check(not FileAccess.file_exists(session_file), "confirmed Claude Code reset archives session reference")
    check(JsonStore.read_dict(other_session, {}).get("session") == "other-provider-sentinel", "Claude Code reset preserves other provider reference")
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "", "fresh Claude Code session works after reset")
    var settings = app.metadata.global_settings()
    settings.auto_approve_reloads = true
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("reload")
    await idle()
    check(app.agent.last_error == "" and app.agent.pending_reload.is_empty(), "Claude Code automatic reload approval completes through streaming JSON and MCP")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    for flag in ["GAMESMITH_CLAUDE_STUCK_START", "GAMESMITH_CLAUDE_STUCK_TURN"]:
        OS.set_environment(flag, "1")
        app.agent.restart_runtime()
        app.agent.send_player_request("wait")
        await create_timer(0.7).timeout
        var start = Time.get_ticks_msec()
        app.agent.cancel()
        await idle()
        check(Time.get_ticks_msec() - start < 8000 and app.agent.rpc == null, "Claude Code Stop force-retires a stuck backend: " + flag)
        OS.unset_environment(flag)
        app.agent.send_player_request("follow up")
        await idle()
        check(app.agent.last_error == "", "Claude Code resumes after forced Stop")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
