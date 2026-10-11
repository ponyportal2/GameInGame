extends SceneTree

var failures := 0
var app
var live := false

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if value:
        print("PASS: " + message)
    else:
        failures += 1
        push_error(message)

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy:
        await process_frame

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "OpenCode acceptance"
    app.harness_option.select(2)
    app._create_game()
    await request("Create a minimal main.gd extending Node with a variable acceptance_marker = 37. Use write. Then call gamesmith_start_test_game in headless mode, gamesmith_read_test_log until startup finishes, and gamesmith_stop_test_game. Do not call gamesmith_reload_game for this request. Finish with ACCEPTANCE_CREATED. Do not use shell commands or delegate work.")
    check(app.agent.last_error == "", "real OpenCode request completes")
    check(FileAccess.file_exists(app.store.game_path(app.current_game).path_join("main.gd")), "OpenCode writes the game through native tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "OpenCode executes the separate testing bridge")
    var session_path = app.metadata.game_meta_dir(app.current_game).path_join("opencode/session.json")
    var original = JsonStore.read_dict(session_path, {}).get("session", "")
    check(original != "", "native OpenCode session is saved")
    var old_game = app.current_game
    app._show_library()
    app._open_game(old_game)
    await request("What value did you put in acceptance_marker in our previous conversation? Do not read files or use tools; answer from conversation history. Include RESUMED_37 if it was 37. Do not reload the game.")
    check(app.agent.last_error == "" and "RESUMED_37" in app.agent.result_text, "reopening resumes native conversation history")
    check(JsonStore.read_dict(session_path, {}).get("session", "") == original, "resume retains the same isolated session")
    app.agent.send_player_request("Run gamesmith_start_test_game in headless mode on our current game, inspect gamesmith_read_test_log until startup completes, stop with gamesmith_stop_test_game, then call gamesmith_reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED only after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty():
        await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "native OpenCode reload waits for player approval")
    if not app.agent.pending_reload.is_empty():
        print("Holding native reload approval for 65 seconds to verify MCP progress keeps it pending.")
        await create_timer(65).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty() and not app.runner.has_active_game(), "native reload survives the MCP default deadline without executing game code")
        app.agent.approve_reload()
        while app.agent.busy:
            await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game(), "real OpenCode approved reload completes")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
