extends SceneTree
var failures := 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value:
        failures += 1

func wait_idle(keep_recovery := false) -> void:
    # Isolate native lifecycle failures; shared recovery has its own matrix.
    if not keep_recovery: app.agent.recovery_delays = []
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
    var backend_before = JsonStore.read_dict(app.metadata.game_meta_dir(app.current_game).path_join("opencode/backend.json"), {})
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "OpenCode bridge starts and gracefully stops a test")
    check(not backend_before.is_empty() and JsonStore.read_dict(app.metadata.game_meta_dir(app.current_game).path_join("opencode/backend.json"), {}).get("pid") == backend_before.get("pid"), "consecutive messages reuse one OpenCode backend")
    app.agent.send_player_request("reload")
    await wait_reload()
    var old_pid = app.agent.rpc.pid
    var child_pids = JsonStore.read_dict(app.tools.workspace.path_join(".opencode-fixture-pids.json"), {})
    app.agent.cancel()
    await wait_idle()
    check(not app.agent.busy and app.agent.pending_reload.is_empty(), "Stop cancels OpenCode and pending reload")
    check(OS.is_process_running(old_pid), "native Stop retains the adapter for the next request")
    check(process_alive(int(child_pids.get("cli", -1))) and process_alive(int(child_pids.get("mcp", -1))), "native Stop retains the backend and MCP connection")
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
    var game = app.current_game
    var workspace = app.tools.workspace
    var source_bytes = FileAccess.get_file_as_bytes(workspace.path_join("main.gd"))
    var command_path = app.metadata.game_meta_dir(game).path_join("command-code/session.json")
    JsonStore.write_dict(command_path, {"session": "other-provider"})
    var command_bytes = FileAccess.get_file_as_bytes(command_path)
    app._show_library()
    JsonStore.write_dict(session_file, {"session": "ses_missing"})
    var stale_bytes = FileAccess.get_file_as_bytes(session_file)
    app._open_game(game)
    app.agent.recovery_delays = [0.02, 0.02, 0.02, 0.02]
    app.agent.send_player_request("follow up")
    await wait_idle(true)
    check(app.agent.recovery_attempt == 0, "stale OpenCode session bypasses automatic retries")
    check("Start a new OpenCode session in Settings" in app.agent.last_error, "stale OpenCode session names the available recovery action")
    check(app.agent.rpc == null or not app.agent.rpc.running, "failed OpenCode initialization retires its adapter")
    check(FileAccess.get_file_as_bytes(session_file) == stale_bytes, "failed resume preserves the exact native reference")
    var history_before = app.chat_history.read_all(game)
    app._open_settings()
    check(app.codex_new_session_button.visible and not app.codex_new_session_button.disabled and "OpenCode" in app.codex_new_session_button.text, "stale OpenCode recovery exposes the enabled Settings action")
    app._request_new_codex_session()
    check(app.codex_session_dialog.visible, "OpenCode recovery requires confirmation")
    app._cancel_new_codex_session()
    check(FileAccess.get_file_as_bytes(session_file) == stale_bytes, "cancelled recovery keeps the stale reference")
    app._request_new_codex_session()
    app._confirm_new_codex_session()
    check(not FileAccess.file_exists(session_file), "confirmed recovery removes the active OpenCode reference")
    var archived = false
    for file in DirAccess.get_files_at(ProjectSettings.globalize_path(session_file.get_base_dir())):
        if file.begins_with("session.previous-"):
            archived = archived or FileAccess.get_file_as_bytes(session_file.get_base_dir().path_join(file)) == stale_bytes
    check(archived, "confirmed recovery archives the exact stale reference")
    check(app.chat_history.read_all(game).slice(0, history_before.size()) == history_before and FileAccess.get_file_as_bytes(workspace.path_join("main.gd")) == source_bytes and FileAccess.get_file_as_bytes(command_path) == command_bytes, "OpenCode recovery preserves chat, game source and other provider reference")
    app.agent.send_player_request("follow up")
    await wait_idle()
    var fresh = JsonStore.read_dict(session_file, {}).get("session", "")
    check(app.agent.last_error == "" and fresh != "" and fresh != "ses_missing", "request after reset creates a fresh native OpenCode session")
    var config_path = session_file.get_base_dir().path_join("runtime.json")
    check(JsonStore.read_dict(config_path, {}).get("session") == "", "first runtime after reset starts without a native session reference")
    app.agent.restart_runtime()
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "" and JsonStore.read_dict(config_path, {}).get("session") == fresh and JsonStore.read_dict(session_file, {}).get("session") == fresh, "replacement backend resumes the fresh OpenCode session")
    settings.auto_approve_reloads = false
    app.metadata.save_global_settings(settings)
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_OPENCODE_BIN")
    quit(1 if failures else 0)
