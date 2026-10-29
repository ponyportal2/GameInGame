extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0
const REQUIRED_TOOLS = ["gamesmith_read", "gamesmith_write", "gamesmith_edit", "gamesmith_search", "gamesmith_list", "gamesmith_start_test_game", "gamesmith_read_test_log", "gamesmith_stop_test_game", "gamesmith_inspect_runtime", "gamesmith_set_properties", "gamesmith_reload_game", "gamesmith_git_commit"]
func check_model(directory: String, stage: String) -> void:
    var data = JsonStore.read_dict(directory.path_join("backend.json"), {})
    var model = str(data.get("model", ""))
    print("OMP native model (%s): %s" % [stage, model])
    # The expected model is optional: without it, a non-empty native choice is
    # enough. The host surface grows with GameSmith, so a frozen tool count
    # rots; assert that only GameSmith tools reached the model and that the
    # core set is present.
    var expected = OS.get_environment("GAMESMITH_TEST_OMP_MODEL")
    if expected != "":
        check(model == expected, "OMP uses the expected native model on " + stage)
    else:
        check(model != "", "OMP reports its effective native model on " + stage)
    var tools: Array = data.get("tools", [])
    var foreign = tools.filter(func(name): return not str(name).begins_with("gamesmith_"))
    var missing = REQUIRED_TOOLS.filter(func(name): return not tools.has(name))
    check(foreign.is_empty() and missing.is_empty(), "OMP exposes only the GameSmith host tool surface on " + stage)

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy:
        if not app.agent.pending_reload.is_empty():
            check(false, "OMP requested reload during a history/no-reload request")
            app.agent.cancel()
        await process_frame
    if app.agent.last_error != "": print("OMP acceptance error: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "OMP native-model acceptance"
    app.harness_option.select(13)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use gamesmith_write with relative path main.gd. Then use gamesmith_start_test_game in headless mode, inspect gamesmith_read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith_stop_test_game; do not poll for a running test to exit by itself. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use only GameSmith tools; no shell or delegation.")
    if app.agent.last_error != "":
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live OMP RPC turn completes")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "OMP writes the requested game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "OMP runs the host headless test bridge")
    check(assistant_deltas > 0, "OMP streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("omp")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    check_model(directory, "new session")
    check(original != "", "native OMP thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "next OMP message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live OMP messages reuse one RPC backend")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "reopening resumes native OMP history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same OMP thread")
    check_model(directory, "reopen")
    app.rename_target = game
    app.rename_edit.text = "Renamed OMP acceptance"
    app._rename_game()
    check(app.current_game == "Renamed OMP acceptance", "OMP game can be renamed after a native turn")
    directory = app.metadata.game_meta_dir(app.current_game).path_join("omp")
    session_file = directory.path_join("session.json")
    app._show_library()
    app._open_game("Renamed OMP acceptance")
    await request("What value did you put in acceptance_marker? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "renaming and reopening retain native OMP history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "rename retains the exact native conversation")
    check_model(directory, "rename/reopen")
    app.agent.send_player_request("Run a fresh headless test with gamesmith_start_test_game, inspect gamesmith_read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with gamesmith_stop_test_game, then call gamesmith_reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live OMP reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live OMP reload does not execute code")
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "OMP approval survives more than 60 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live OMP approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("Call gamesmith_reload_game on the game we already tested. Wait for approval; do not edit files.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live OMP reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native OMP Stop settles pending reload")
        await request("Answer from our conversation without tools. What value did you put in acceptance_marker? Reply with only the decimal integer. Do not reload.")
        check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "live OMP resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend, "live Stop starts a clean backend and resumes history")
        check_model(directory, "Stop/resume")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
