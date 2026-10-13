extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0

func check_model(directory: String, stage: String) -> void:
    if app.agent.last_error != "":
        check(false, "Cannot verify Crush HTTP model after failed " + stage)
        return
    var actual = str(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("model", ""))
    var expected = OS.get_environment("GAMESMITH_TEST_CRUSH_MODEL")
    print("Crush native model (%s): %s" % [stage, actual])
    if expected != "":
        check(actual == expected, "Crush uses the expected HTTP model on " + stage)
    else:
        check(actual != "", "Crush reports its effective HTTP model on " + stage)

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy:
        if not app.agent.pending_reload.is_empty():
            check(false, "Crush requested reload during a history/no-reload request")
            app.agent.cancel()
        await process_frame
    if app.agent.last_error != "": print("Crush acceptance error: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Crush native-model acceptance"
    app.harness_option.select(12)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use mcp_gamesmith_write with relative path main.gd. Then use mcp_gamesmith_start_test_game in headless mode, inspect mcp_gamesmith_read_test_log: state=running and load_result.ok=true means startup succeeded. Stop that run with mcp_gamesmith_stop_test_game; do not poll for a running test to exit by itself. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use only GameSmith tools; no shell or delegation.")
    if app.agent.last_error != "":
        app.queue_free()
        await process_frame
        quit(1)
        return
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live Crush HTTP turn completes")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "Crush writes the requested game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "Crush runs the host headless test bridge")
    check(assistant_deltas > 0, "Crush streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("crush")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    check_model(directory, "new session")
    check(original != "", "native Crush thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "next Crush message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Crush messages reuse one app-server")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "reopening resumes native Crush history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same Crush thread")
    check_model(directory, "reopen")
    app.rename_target = game
    app.rename_edit.text = "Renamed Crush acceptance"
    app._rename_game()
    check(app.current_game == "Renamed Crush acceptance", "Crush game can be renamed after a native turn")
    directory = app.metadata.game_meta_dir(app.current_game).path_join("crush")
    session_file = directory.path_join("session.json")
    app._show_library()
    app._open_game("Renamed Crush acceptance")
    await request("What value did you put in acceptance_marker? Answer from conversation history without files or tools. Reply with only the decimal integer. Do not reload.")
    check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "renaming and reopening retain native Crush history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "rename retains the exact native conversation")
    check_model(directory, "rename/reopen")
    app.agent.send_player_request("The unchanged game already passed the headless test earlier in this conversation. Explicitly call mcp_gamesmith_reload_game NOW. This is a new request to reload, replacing the earlier no-reload instruction. Do not edit files or run another test. Wait for player approval. Finish with RELOAD_ACCEPTED after this reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live Crush reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live Crush reload does not execute code")
        await create_timer(65.0).timeout
        check(app.agent.busy and not app.agent.pending_reload.is_empty(), "Crush approval survives more than 60 seconds")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live Crush approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("For this new request, explicitly call mcp_gamesmith_reload_game again NOW on the already tested game. I am asking for another reload even though the previous reload succeeded. Wait for approval; do not edit files and do not just report the earlier result.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live Crush reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native Crush Stop settles pending reload")
        await request("Answer from our conversation without tools. What value did you put in acceptance_marker? Reply with only the decimal integer. Do not reload.")
        check(app.agent.last_error == "" and app.agent.result_text.strip_edges().split("\n")[-1].strip_edges() == "37", "live Crush resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") != backend, "live Stop starts a clean backend and resumes history")
        check_model(directory, "Stop/resume")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
