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
    app.name_edit.text = "Command-code acceptance"
    app.harness_option.select(1)
    app._create_game()
    await request("Create a minimal main.gd extending Node with a variable acceptance_marker = 37. Use write_file. Then call start_test_game in headless mode, read_test_log until startup finishes, and stop_test_game. Do not call reload_game for this request. Finish with ACCEPTANCE_CREATED. Do not use shell commands or delegate work.")
    check(app.agent.last_error == "", "real command-code request completes")
    check(FileAccess.file_exists(app.store.game_path(app.current_game).path_join("main.gd")), "command-code writes the game through native tools")
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.metadata.game_meta_dir(app.current_game).path_join("tests"))), "command-code executes the separate testing bridge")
    var session_path = app.metadata.game_meta_dir(app.current_game).path_join("command-code/session.json")
    var original = JsonStore.read_dict(session_path, {}).get("session", "")
    check(original != "", "native command-code session is saved")
    var old_game = app.current_game
    app._show_library()
    app._open_game(old_game)
    await request("What value did you put in acceptance_marker in our previous conversation? Do not read files or use tools; answer from conversation history. Include RESUMED_37 if it was 37. Do not reload the game.")
    check(app.agent.last_error == "" and "RESUMED_37" in app.agent.result_text, "reopening resumes native conversation history")
    check(JsonStore.read_dict(session_path, {}).get("session", "") == original, "resume retains the same isolated session")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
