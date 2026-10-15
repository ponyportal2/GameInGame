extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if not value: failures += 1
func idle(agent) -> void:
    var deadline = Time.get_ticks_msec() + 20000
    while agent.busy and Time.get_ticks_msec() < deadline: await process_frame
    check(not agent.busy, "native request settles")
func run() -> void:
    # Every executable is a protocol fixture. No provider/model is invoked.
    var harnesses = ["command-code", "opencode", "codex", "cline", "cursor", "grok-build", "agy", "kimi", "kiro", "kilo", "copilot", "crush", "omp"]
    for index in harnesses.size():
        var harness: String = harnesses[index]
        var env_name = "GAMESMITH_" + harness.replace("-", "_").to_upper() + "_BIN"
        if harness == "command-code": env_name = "GAMESMITH_COMMAND_CODE_BIN"
        OS.set_environment(env_name, ProjectSettings.globalize_path("res://tools/testing/fake-" + harness + ".mjs"))
        var app = load("res://main.tscn").instantiate()
        root.add_child(app)
        await process_frame
        app.name_edit.text = "Recovery " + harness
        app.harness_option.select(index + 1)
        app._create_game()
        # Exercise real IPC/retirement/resume while avoiding 8 seconds per fixture.
        app.agent.recovery_delays = [0.02, 0.02, 0.02, 0.02]
        app.agent.send_player_request("follow up")
        await idle(app.agent)
        check(app.agent.last_error == "", harness + " establishes native conversation")
        var session_file = app.metadata.game_meta_dir(app.current_game).path_join(harness + "/session.json")
        var saved = JsonStore.read_dict(session_file, {}).get("session", "")
        var old_pid: int = app.agent.rpc.pid if app.agent.rpc != null else -1
        app.agent.send_player_request("provider-error")
        await idle(app.agent)
        check(app.agent.last_error == "" and app.agent.recovery_attempt == 1, harness + " failed turn automatically continues successfully")
        check(saved != "" and JsonStore.read_dict(session_file, {}).get("session") == saved, harness + " recovery preserves exact native history")
        check(app.agent.rpc != null and app.agent.rpc.pid != old_pid and not OS.is_process_running(old_pid), harness + " retires old adapter before resuming")
        var rows = app.transcript.read_all(app.current_game)
        check(rows.size() == 4 and rows[2].content == "provider-error" and not rows[3].content.begins_with("Error:"), harness + " transcript omits recovery prompts and intermediate errors")
        app.queue_free()
        await process_frame
        OS.unset_environment(env_name)
    quit(1 if failures else 0)
