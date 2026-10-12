extends SceneTree
var failures := 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value:
        failures += 1

func idle() -> void:
    while app.agent.busy:
        await process_frame

func process_alive(pid: int) -> bool:
    var output: Array = []
    if OS.get_name() != "Windows":
        var code = OS.execute("ps", ["-p", str(pid), "-o", "stat="], output)
        var state = str(output[0]).strip_edges() if not output.is_empty() else ""
        return code == 0 and state != "" and not state.begins_with("Z")
    OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], output, true)
    return not output.is_empty() and ('"%d"' % pid) in str(output[0])

func count_compactions() -> int:
    var path = app.agent.tools.workspace.path_join(".compaction-fixture.jsonl")
    return FileAccess.get_file_as_string(path).strip_edges().split("\n").size() if FileAccess.file_exists(path) else 0

func run() -> void:
    OS.set_environment("GAMESMITH_COMMAND_CODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-command-code.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    var original = app.metadata.global_settings().duplicate(true)
    var settings = original.duplicate(true)
    settings.compaction_auto_tokens = 0
    app.metadata.save_global_settings(settings)
    app.name_edit.text = "Command compaction fixture"
    app.harness_option.select(1)
    app._create_game()
    app.agent.send_player_request("large-context")
    await idle()
    check(app.agent.last_context_tokens == 65020 and count_compactions() == 0, "zero disables host trigger; cached context counts")
    settings.compaction_auto_tokens = 65020
    app.metadata.save_global_settings(settings)
    app.agent.send_player_request("follow up")
    await idle()
    check(count_compactions() == 1 and app.agent.last_error == "", "threshold equality compacts saved session before next request")
    app.agent.send_player_request("large-context")
    await idle()
    check(count_compactions() == 2 and app.agent.last_context_tokens == 25000, "completed turn compacts once and updates native usage")
    app.agent.send_player_request("follow up")
    await idle()
    check(count_compactions() == 2, "below threshold sends request without compaction")
    var game = app.current_game
    app._show_library()
    app._open_game(game)
    var result: Dictionary = await app.agent.compact_now()
    check(result.get("ok", false) and app.agent.last_context_tokens == 25000, "manual compaction after reopen uses saved native UUID")
    OS.set_environment("GAMESMITH_FAKE_COMPACTION", "failed")
    app.agent.rpc.retire()
    result = await app.agent.compact_now()
    check(not result.get("ok", true) and result.get("error", "") != "", "native summary failure reports failure")
    settings.compaction_auto_tokens = 1
    app.metadata.save_global_settings(settings)
    var attempts = count_compactions()
    app.agent.send_player_request("follow up")
    await idle()
    check(count_compactions() == attempts + 1 and app.agent.auto_compaction_failed_operation == app.agent.operation_id, "automatic failure blocks request and does not retry in same turn")
    settings.compaction_auto_tokens = 65020
    app.metadata.save_global_settings(settings)
    OS.set_environment("GAMESMITH_FAKE_COMPACTION", "too-small")
    app.agent.rpc.retire()
    result = await app.agent.compact_now()
    check(result.get("no_op", false) and not result.get("ok", true), "small conversation reports skipped compaction")
    OS.set_environment("GAMESMITH_FAKE_COMPACTION", "slow")
    app.agent.rpc.retire()
    var pending = count_compactions()
    app.agent.compact_now()
    while count_compactions() == pending:
        await process_frame
    var pid = app.agent.rpc.pid
    var log_path = app.agent.tools.workspace.path_join(".compaction-fixture.jsonl")
    var last_line = FileAccess.get_file_as_string(log_path).strip_edges().split("\n")[-1]
    var child_pid = int(JSON.parse_string(last_line).pid)
    app.agent.cancel()
    await create_timer(0.2).timeout
    check(not app.agent.busy and not process_alive(pid) and not process_alive(child_pid), "Stop cancels adapter and native compaction child")
    OS.unset_environment("GAMESMITH_FAKE_COMPACTION")
    app.agent.send_player_request("follow up")
    await idle()
    check(app.agent.last_error == "", "saved conversation resumes after cancelled compaction")
    app.metadata.save_global_settings(original)
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_COMMAND_CODE_BIN")
    quit(1 if failures else 0)
