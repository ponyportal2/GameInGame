extends SceneTree
var failures := 0
var app
var assistant_deltas := 0
var thinking_deltas := 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(text: String) -> void:
    app.agent.send_player_request(text)
    while app.agent.busy: await process_frame

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Codex Luna acceptance"
    app.harness_option.select(3)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": assistant_deltas += 1
        if kind == "thinking": thinking_deltas += 1)
    await request("Create a minimal main.gd extending Node with var acceptance_marker = 37. Use gamesmith_write. Then use gamesmith_start_test_game in headless mode, inspect gamesmith_read_test_log until startup completes, and gamesmith_stop_test_game. Do not reload for this request. Finish with ACCEPTANCE_CREATED. Use only GameSmith tools; no shell or delegation.")
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "live Luna/xhigh Codex turn completes")
    check(FileAccess.file_exists(app.tools.workspace.path_join("main.gd")), "Codex writes the game through workspace tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "Codex runs the host headless test bridge")
    check(assistant_deltas > 0, "Codex streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("codex")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    var native_settings = JsonStore.read_dict(directory.path_join("backend.json"), {})
    check(native_settings.get("model") == "gpt-6-luna" and native_settings.get("reasoning_effort") == "xhigh", "native Codex confirms Luna and xhigh test settings")
    check(original != "", "native Codex thread is saved")
    await request("What value did you put in acceptance_marker in our previous turn? Answer from conversation history without files or tools. Include REUSED_37 if it was 37. Do not reload.")
    check(app.agent.last_error == "" and "REUSED_37" in app.agent.result_text, "next Codex message reuses conversation history")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live Codex messages reuse one app-server")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    await request("What value did you put in acceptance_marker in our previous conversation? Answer from history without files or tools. Include RESUMED_37 if it was 37. Do not reload.")
    check(app.agent.last_error == "" and "RESUMED_37" in app.agent.result_text, "reopening resumes native Codex history")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "reopen retains the same Codex thread")
    app.agent.send_player_request("Run a fresh headless test with gamesmith_start_test_game, inspect gamesmith_read_test_log until startup completes, stop it with gamesmith_stop_test_game, then call gamesmith_reload_game. Wait for player approval. Finish with RELOAD_ACCEPTED after reload succeeds.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "live Codex reload waits for approval")
    if not app.agent.pending_reload.is_empty():
        check(not app.runner.has_active_game(), "pending live Codex reload does not execute code")
        app.agent.approve_reload()
        while app.agent.busy: await process_frame
        check(app.agent.last_error == "" and app.runner.has_active_game() and "RELOAD_ACCEPTED" in app.agent.result_text, "live Codex approved reload completes")
    backend = JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid")
    app.agent.send_player_request("Call gamesmith_reload_game on the game we already tested. Wait for approval; do not edit files.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "live Codex reaches reload approval for Stop")
    if not app.agent.pending_reload.is_empty():
        app.agent.cancel()
        while app.agent.busy: await process_frame
        check(app.agent.pending_reload.is_empty() and app.agent.last_error == "", "live native Codex Stop settles pending reload")
        await request("Answer from our conversation without tools. Include AFTER_STOP_37 if acceptance_marker was 37. Do not reload.")
        check(app.agent.last_error == "" and "AFTER_STOP_37" in app.agent.result_text, "live Codex resumes after native Stop")
        check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend, "live native Stop retains the app-server")
    print("Live thinking deltas: %d" % thinking_deltas)
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
