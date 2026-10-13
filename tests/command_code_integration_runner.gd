extends SceneTree

var failures := 0
var app
var live := false
var streamed := false

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
    app.name_edit.text = "Command-code acceptance"
    app.harness_option.select(1)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(_kind, text):
        if text != "": streamed = true)
    await request("Create a minimal main.gd extending Node with a variable acceptance_marker = 37. Use write_file. Then call start_test_game in headless mode, read_test_log until startup finishes, and stop_test_game. Do not call reload_game for this request. Finish with ACCEPTANCE_CREATED. Do not use shell commands or delegate work.")
    check(app.agent.last_error == "", "real command-code request completes")
    check(FileAccess.file_exists(app.store.game_path(app.current_game).path_join("main.gd")), "command-code writes the game through native tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "command-code executes the separate testing bridge")
    var session_path = app.metadata.game_meta_dir(app.current_game).path_join("command-code/session.json")
    var original = JsonStore.read_dict(session_path, {}).get("session", "")
    check(original != "", "native command-code session is saved")
    check(streamed, "native ACP streams incremental agent output")
    var first_backend = app.agent.backend_pid
    await request("Reply SECOND_TURN_OK. Do not use tools or reload. Remember acceptance_marker was 37.")
    check(app.agent.last_error == "" and app.agent.backend_pid == first_backend, "ordinary turns reuse the same ACP backend")
    var old_game = app.current_game
    app._show_library()
    app._open_game(old_game)
    await request("What value did you put in acceptance_marker in our previous conversation? Do not read files or use tools; answer from conversation history. Include RESUMED_37 if it was 37. Do not reload the game.")
    check(app.agent.last_error == "" and "RESUMED_37" in app.agent.result_text, "reopening resumes native conversation history")
    check(JsonStore.read_dict(session_path, {}).get("session", "") == original, "resume retains the same isolated session")
    app.agent.send_player_request("Headless test the existing game, read its test log until startup completes, stop the test, then call reload_game. Wait for approval. Do not edit the game. Finish RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "real reload waits for player approval")
    if not app.agent.pending_reload.is_empty():
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "real reload approval remains pending after 65 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game(), "approved reload completes successfully")
    app.agent.send_player_request("Call reload_game again now. The same files already passed headless testing. Wait for player approval and do nothing else.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    var stopped_backend = app.agent.backend_pid
    app.agent.cancel()
    await process_frame
    check(not OS.is_process_running(stopped_backend), "Stop terminates the native ACP backend")
    await request("From conversation history, what was acceptance_marker? Do not use tools. Reply STOP_RESUMED_37 if it was 37.")
    check(app.agent.last_error == "" and "STOP_RESUMED_37" in app.agent.result_text, "Stop resumes native conversation history")
    check(JsonStore.read_dict(session_path, {}).get("session", "") == original, "Stop preserves the exact native session ID")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
