extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0

func check_model(directory: String, stage: String) -> void:
    if app.agent.last_error != "":
        check(false, "Cannot verify Kilo HTTP/SSE model after failed " + stage)
        return
    var actual = str(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("model", ""))
    var expected = OS.get_environment("GAMESMITH_TEST_KILO_MODEL")
    print("Kilo native model (%s): %s" % [stage, actual])
    if expected != "":
        check(actual == expected, "Kilo uses the expected HTTP/SSE model on " + stage)
    else:
        check(actual != "", "Kilo reports its effective HTTP/SSE model on " + stage)

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy: await process_frame
    if app.agent.last_error != "": print("Kilo acceptance error: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Kilo native-model acceptance"
    app.harness_option.select(10)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use native write with filePath pointing to main.gd in the workspace. Then use gamesmith_start_test_game in headless mode, inspect gamesmith_read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith_stop_test_game; do not poll for a running test to exit by itself. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use native file tools and GameSmith MCP tools; no shell or delegation.")
    if app.agent.last_error != "":
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live Kilo HTTP/SSE turn completes")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "Kilo writes the requested game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "Kilo runs the host headless test bridge")
    check(assistant_deltas > 0, "Kilo streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("kilo")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    check_model(directory, "new session")
    check(original != "", "native Kilo thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "next Kilo message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Kilo messages reuse one backend")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "reopening resumes native Kilo history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same Kilo thread")
    check_model(directory, "reopen")
    var renamed = app.store.rename_game(game, "Renamed Kilo acceptance")
    check(not renamed.get("ok", true) and "Kilo" in renamed.get("error", ""), "Kilo rename explains native workspace binding")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.tools.workspace)), "rejected rename keeps the game workspace")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "rejected rename preserves the exact native conversation")
    check_model(directory, "rejected rename")
    app.agent.send_player_request("Run a fresh headless test with gamesmith_start_test_game, inspect gamesmith_read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith_stop_test_game, then call gamesmith_reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live Kilo reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live Kilo reload does not execute code")
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Kilo approval survives more than 60 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live Kilo approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("Call gamesmith_reload_game on the game we already tested. Wait for approval; do not edit files.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live Kilo reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native Kilo Stop settles pending reload")
        await request("Answer from our conversation without tools. What value did you put in acceptance_marker? Reply with only the decimal integer. Do not reload.")
        check(app.agent.last_error == "" and app.agent.result_text.strip_edges() == "37", "live Kilo resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Stop reuses the backend and resumes history")
        check_model(directory, "Stop/resume")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
