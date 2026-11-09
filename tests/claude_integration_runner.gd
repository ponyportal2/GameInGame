extends SceneTree

var failures := 0
var app
var streamed := 0

func _init() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value: failures += 1

func request(message: String) -> void:
    app.agent.send_player_request(message)
    while app.agent.busy: await process_frame
    if app.agent.last_error != "": print("Claude Code acceptance: " + app.agent.last_error)

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Claude Code native acceptance"
    for item in app.harness_option.item_count:
        if str(app.harness_option.get_item_metadata(item)) == "claude": app.harness_option.select(item)
    app._create_game()
    app.agent.recovery_delays = []
    app.agent.llm_stream_delta.connect(func(kind, _text):
        if kind == "assistant": streamed += 1)
    await request("Write main.gd containing exactly extends Node followed by var acceptance_marker = 37 on a new line. Use the GameSmith write tool. Start a headless test, read its log once to confirm running and successful load, then stop it. Do not reload yet. Reply ACCEPTANCE_CREATED.")
    check(app.agent.last_error == "" and "ACCEPTANCE_CREATED" in app.agent.result_text, "installed Claude Code completes a game-edit and detached-test turn")
    check("acceptance_marker = 37" in FileAccess.get_file_as_string(app.tools.workspace.path_join("main.gd")), "installed Claude Code writes the requested game")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "installed Claude Code exercises detached testing")
    check(streamed > 0, "installed Claude Code streams assistant text")
    var directory = app.metadata.game_meta_dir(app.current_game).path_join("claude")
    var session_file = directory.path_join("session.json")
    var original = JsonStore.read_dict(session_file, {}).get("session", "")
    var backend = JsonStore.read_dict(directory.path_join("backend.json"), {})
    check(original != "" and backend.get("model", "") != "", "native session and selected model are recorded")
    app.agent.send_player_request("Call reload_game for the game we just tested. Do not edit or test again. Wait for approval, then reply RELOAD_ACCEPTED.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty() and not app.runner.has_active_game(), "installed Claude Code waits for host reload consent")
    if not app.agent.pending_reload.is_empty(): app.agent.approve_reload()
    while app.agent.busy: await process_frame
    check(app.agent.last_error == "" and app.runner.has_active_game(), "installed Claude Code approved reload passes preflight and loads")
    check(JsonStore.read_dict(directory.path_join("backend.json"), {}).get("pid") == backend.get("pid"), "ordinary installed Claude Code turns reuse their backend")
    app.agent.send_player_request("Call reload_game again, without editing or testing. Wait for approval.")
    while app.agent.busy and app.agent.pending_reload.is_empty(): await process_frame
    check(not app.agent.pending_reload.is_empty(), "installed Claude Code reaches approval before Stop")
    app.agent.cancel()
    while app.agent.busy: await process_frame
    check(app.agent.pending_reload.is_empty() and app.agent.rpc == null, "installed Claude Code Stop clears consent and retires its backend")
    await request("What value did we put in acceptance_marker earlier? Answer only HISTORY_37 if it was 37, from conversation history without tools.")
    check(app.agent.last_error == "" and "HISTORY_37" in app.agent.result_text, "installed Claude Code resumes history after Stop")
    check(JsonStore.read_dict(session_file, {}).get("session") == original, "Stop continuation retains the native session")
    print("Native Claude Code model: " + str(backend.get("model", "")))
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
