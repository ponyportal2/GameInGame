extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0

func check_model(directory: String, stage: String) -> void:
    if app.agent.last_error != "":
        check(false, "Cannot verify Kiro ACP model after failed " + stage)
        return
    var actual = str(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("model", ""))
    var expected = OS.get_environment("GAMESMITH_TEST_KIRO_MODEL")
    print("Kiro native model (%s): %s" % [stage, actual])
    if expected != "":
        check(actual == expected, "Kiro uses the expected ACP model on " + stage)
    else:
        check(actual != "", "Kiro reports its effective ACP model on " + stage)

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy: await process_frame
    if app.agent.last_error != "": print("Kiro acceptance error: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Kiro native-model acceptance"
    app.harness_option.select(9)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use @gamesmith/write with relative path main.gd. Then use @gamesmith/start_test_game in headless mode, inspect @gamesmith/read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with @gamesmith/stop_test_game; do not poll for a running test to exit by itself. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use only GameSmith tools; no shell or delegation.")
    if app.agent.last_error != "":
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live Kiro ACP turn completes")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "Kiro writes the requested game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "Kiro runs the host headless test bridge")
    check(assistant_deltas > 0, "Kiro streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("kiro")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    check_model(directory, "new session")
    check(original != "", "native Kiro thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "next Kiro message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Kiro messages reuse one app-server")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "reopening resumes native Kiro history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same Kiro thread")
    check_model(directory, "reopen")
    app.rename_target = game
    app.rename_edit.text = "Renamed Kiro acceptance"
    app._rename_game()
    check(app.current_game == "Renamed Kiro acceptance", "Kiro game can be renamed after a native turn")
    directory = app.metadata.game_meta_dir(app.current_game).path_join("kiro")
    session_file = directory.path_join("session.json")
    app._show_library()
    app._open_game("Renamed Kiro acceptance")
    await request("What value did you put in acceptance_marker? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "renaming and reopening retain native Kiro history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "rename retains the exact native conversation")
    check_model(directory, "rename/reopen")
    app.agent.send_player_request("Run a fresh headless test with @gamesmith/start_test_game, inspect @gamesmith/read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with @gamesmith/stop_test_game, then call @gamesmith/reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live Kiro reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live Kiro reload does not execute code")
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Kiro approval survives more than 60 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live Kiro approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("Call @gamesmith/reload_game on the game we already tested. Wait for approval; do not edit files.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live Kiro reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native Kiro Stop settles pending reload")
        await request("Answer from our conversation without tools. What value did you put in acceptance_marker? Reply with only the decimal integer. Do not reload.")
        check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "live Kiro resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend, "live Stop starts a clean backend and resumes history")
        check_model(directory, "Stop/resume")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
