extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0

func check_model(directory: String, stage: String) -> void:
    if app.agent.last_error != "":
        check(false, "Cannot verify Grok Build ACP model after failed " + stage)
        return
    var actual = str(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("model", ""))
    var expected = OS.get_environment("GAMESMITH_TEST_GROK_BUILD_MODEL")
    print("Grok Build native model (%s): %s" % [stage, actual])
    if expected != "":
        check(actual == expected, "Grok Build uses the expected ACP model on " + stage)
    else:
        check(actual != "", "Grok Build reports its effective ACP model on " + stage)

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy: await process_frame
    if app.agent.last_error != "": print("Grok Build acceptance error: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Grok Build native-model acceptance"
    app.harness_option.select(6)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use gamesmith__write with relative path main.gd. Then use gamesmith__start_test_game in headless mode, inspect gamesmith__read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith__stop_test_game; do not poll for a running test to exit by itself. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use only GameSmith tools; no shell or delegation.")
    if app.agent.last_error != "":
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live Grok Build ACP turn completes")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "Grok Build writes the requested game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "Grok Build runs the host headless test bridge")
    check(assistant_deltas > 0, "Grok Build streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("grok-build")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    check_model(directory, "new session")
    check(original != "", "native Grok Build thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Include REUSED_37 if it was 37. Do not reload.")
    check(app.agent.last_error == "" and "REUSED_37" in app.agent.result_text, "next Grok Build message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Grok Build messages reuse one app-server")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Include RESUMED_37 if it was 37. Do not reload.")
    check(app.agent.last_error == "" and "RESUMED_37" in app.agent.result_text, "reopening resumes native Grok Build history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same Grok Build thread")
    check_model(directory, "reopen")
    app.agent.send_player_request("Run a fresh headless test with gamesmith__start_test_game, inspect gamesmith__read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith__stop_test_game, then call gamesmith__reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live Grok Build reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live Grok Build reload does not execute code")
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Grok Build approval survives more than 60 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live Grok Build approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("Call gamesmith__reload_game on the game we already tested. Wait for approval; do not edit files.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live Grok Build reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native Grok Build Stop settles pending reload")
        await request("Answer from our conversation without tools. Include AFTER_STOP_37 if acceptance_marker was 37. Do not reload.")
        check(app.agent.last_error == "" and "AFTER_STOP_37" in app.agent.result_text, "live Grok Build resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend, "live Stop starts a clean backend and resumes history")
        check_model(directory, "Stop/resume")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
