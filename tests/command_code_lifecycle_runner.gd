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
    OS.set_environment("GAMESMITH_COMMAND_CODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-command-code.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Command lifecycle"
    app.harness_option.select(1)
    app._create_game()
    app.agent.send_player_request("reload")
    await wait_reload()
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "command-code reload waits for approval")
    check(not app.runner.has_active_game(), "pending reload does not execute game code")
    app.agent.approve_reload()
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "approved reload finishes the command-code request")
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "command-code bridge starts and gracefully stops a test")
    app.agent.send_player_request("reload")
    await wait_reload()
    var old_pid = app.agent.rpc.pid
    app.agent.cancel()
    await process_frame
    check(not app.agent.busy and app.agent.pending_reload.is_empty(), "Stop cancels command-code and pending reload")
    check(not OS.is_process_running(old_pid), "Stop terminates the adapter process")
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "", "a new request works after cancellation")
    var settings = app.metadata.global_settings()
    settings.auto_approve_reloads = true
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("repair-reload")
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.active_game.get("repaired") == true, "failed reload diagnostics let command-code repair, test and reload in the same request")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    var session_file = app.metadata.game_meta_dir(app.current_game).path_join("command-code/session.json")
    var game = app.current_game
    app._show_library()
    JsonStore.write_dict(session_file, {"session": "missing-native-session"})
    app._open_game(game)
    app.agent.send_player_request("must not infer")
    await wait_idle()
    check("Start a new Command-code session" in app.agent.last_error, "missing native history produces actionable recovery")
    app._open_settings()
    check(app.codex_new_session_button.visible and "Command-code" in app.codex_new_session_button.text, "Command-code settings expose session reset")
    app._request_new_codex_session()
    app._cancel_new_codex_session()
    check(JsonStore.read_dict(session_file, {}).get("session") == "missing-native-session", "cancelled reset preserves the native reference")
    app._request_new_codex_session()
    app._confirm_new_codex_session()
    check(not FileAccess.file_exists(session_file), "confirmed reset clears the active native reference")
    var archived = false
    for file in DirAccess.get_files_at(ProjectSettings.globalize_path(session_file.get_base_dir())):
        if file.begins_with("session.previous-"):
            archived = JsonStore.read_dict(session_file.get_base_dir().path_join(file), {}).get("session") == "missing-native-session"
    check(archived, "reset archives the original reference")
    app.rename_target = game
    app.rename_edit.text = "Command lifecycle after reset"
    app._rename_game()
    check(app.current_game == "Command lifecycle after reset", "rename works immediately after reset")
    app.agent.send_player_request("fresh conversation")
    await wait_idle()
    var fresh = JsonStore.read_dict(app.metadata.game_meta_dir(app.current_game).path_join("command-code/session.json"), {}).get("session", "")
    check(app.agent.last_error == "" and fresh != "" and fresh != "missing-native-session", "next turn creates a fresh native session")
    check(not app.store.rename_game(app.current_game, "must stay here").get("ok", true), "native history protects against destructive rename")
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_COMMAND_CODE_BIN")
    quit(1 if failures else 0)
