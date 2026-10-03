extends SceneTree

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const PiRpcSessionScript = preload("res://src/pi/pi_rpc_session.gd")

var failures := 0
var passed := 0
var base_url := ""
var fake_log := ""

func _init() -> void:
    call_deferred("run")

func assert_true(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAIL: " + label)

func assert_eq(actual, expected, label: String) -> void:
    assert_true(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])

func run() -> void:
    base_url = OS.get_environment("GAMESMITH_PI_FAKE_URL")
    fake_log = OS.get_environment("GAMESMITH_PI_FAKE_LOG")
    var part = OS.get_environment("GAMESMITH_PI_TEST_PART").strip_edges()
    assert_true(base_url != "", "Pi integration receives fake OpenAI-compatible base URL")
    assert_true(OS.get_environment("GAMESMITH_PI_BIN") != "", "Pi integration receives explicit globally-installed Pi command for CI")

    if part == "" or part == "1":
        await _test_missing_global_pi_error()
        await _test_known_model_capabilities()
        await _test_production_app_uses_pi()
        await _test_real_pi_separate_process()
        await _test_real_pi_generation_edit_stream_and_restart()
        await _test_real_pi_completion_without_forced_tools()
        await _test_real_pi_retry_and_action_limit()
        await _test_real_pi_cancel_and_rename()

    if part == "" or part == "2":
        await _test_real_pi_manual_and_auto_compaction()

    if part == "" or part == "3":
        await _test_legacy_transcript_import_is_one_time()
        _test_legacy_runtime_sources_are_removed()

    if part == "" or part == "4":
        _test_pi_binary_discovery_modes()
        _test_windows_pi_install_guidance()

    var label = "ALL" if part == "" else "PART " + part
    print("PI %s INTEGRATION TESTS: %d passed, %d failed" % [label, passed, failures])
    quit(0 if failures == 0 else 1)

func _test_missing_global_pi_error() -> void:
    var old = OS.get_environment("GAMESMITH_PI_BIN")
    OS.set_environment("GAMESMITH_PI_BIN", "/definitely/missing/gamesmith-pi")
    var session = PiRpcSessionScript.new()
    var result: Dictionary = session._check_pi_available()
    assert_true(not bool(result.get("ok", false)), "missing configured Pi executable is rejected before process launch")
    assert_true("does not exist" in str(result.get("error", "")).to_lower(), "missing Pi error explains that the configured executable does not exist")
    session.free()
    if old == "":
        OS.unset_environment("GAMESMITH_PI_BIN")
    else:
        OS.set_environment("GAMESMITH_PI_BIN", old)

func _test_known_model_capabilities() -> void:
    var created = _new_game("Pi Catalog")
    assert_true(bool(created.get("ok", false)), "creates Pi catalog capability fixture")
    if not created.get("ok", false):
        return
    var config = preload("res://src/pi/pi_runtime_config.gd").prepare(created.name, created.path, {"provider": "custom", "model": "openai/gpt-4o-mini", "custom_base_url": base_url}, {"custom": "pi-test-key"}, {})
    # Exercise catalog registration through real Pi without making a paid call.
    config.source_provider = "openrouter"
    var rpc = PiRpcSessionScript.new()
    root.add_child(rpc)
    var started = rpc.start(config)
    assert_true(bool(started.get("ok", false)), "starts real Pi for known catalog model")
    if bool(started.get("ok", false)):
        var selected = await rpc.command({"type": "set_model", "provider": "gamesmith", "modelId": "openai/gpt-4o-mini"})
        assert_true(bool(selected.get("success", false)), "selects catalog-backed GameSmith model")
        var model: Dictionary = selected.get("data", {})
        assert_eq(int(model.get("contextWindow", 0)), 128000, "known model uses Pi catalog context window")
        assert_eq(int(model.get("maxTokens", 0)), 16384, "known model uses Pi catalog output limit")
        assert_true(not bool(model.get("reasoning", true)), "known nonreasoning model retains its actual capability")
    rpc.retire()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _settings(model: String, delay_sec: float = 0.0, max_steps: int = 150, auto_tokens: int = 100000, keep_tokens: int = 20000, reasoning: String = "high") -> void:
    var meta = MetadataStoreScript.new()
    var settings = meta.global_settings().duplicate(true)
    settings.provider = "custom"
    settings.model = model
    settings.custom_base_url = base_url
    settings.reasoning_effort = reasoning
    settings.llm_call_delay_sec = delay_sec
    settings.max_agent_steps = max_steps
    settings.compaction_auto_tokens = auto_tokens
    settings.compaction_keep_recent_tokens = keep_tokens
    meta.save_global_settings(settings)
    var creds = meta.credentials().duplicate(true)
    creds.custom = "pi-test-key"
    meta.save_credentials(creds)

func _new_game(prefix: String) -> Dictionary:
    var store = WorkspaceStoreScript.new()
    store.ensure()
    return store.create_game("%s %d" % [prefix, Time.get_ticks_msec()])

func _controller(game_name: String, path: String, runner: Node, auto_approve_reload: bool = true) -> Node:
    var agent = PiAgentControllerScript.new()
    root.add_child(agent)
    agent.configure(game_name, GameToolsScript.new(path, runner))
    if auto_approve_reload:
        agent.reload_approval_changed.connect(func(pending):
            if pending:
                agent.call_deferred("approve_reload")
        )
    return agent

func _test_production_app_uses_pi() -> void:
    var created = _new_game("Pi Production")
    assert_true(bool(created.get("ok", false)), "creates production-controller test game")
    if not created.get("ok", false):
        return
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    await process_frame
    assert_true(is_instance_valid(app.agent) and app.agent.get_script() == PiAgentControllerScript, "production GameSmith App uses PiAgentController instead of the homegrown loop")
    app.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _test_real_pi_separate_process() -> void:
    _settings("pi-gamesmith-test-process", 0.05)
    var created = _new_game("Pi Separate Test")
    var file = FileAccess.open(created.path.path_join("main.gd"), FileAccess.WRITE)
    file.store_string("extends Node\nvar marker = 99\n")
    file.close()
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner, false)
    var text = {"value": ""}
    agent.assistant_message.connect(func(message): text.value += str(message))
    agent.llm_stream_delta.connect(func(kind, delta):
        if kind == "assistant": text.value += str(delta)
    )
    agent.send_player_request("Test the current game in a separate process, inspect marker, and stop it. Do not reload the player's game.")
    var ok = await agent.finished
    assert_true(bool(ok) and "SEPARATE_TEST_VERIFIED" in text.value, "Real Pi launches, inspects, and gracefully stops separate Godot")
    assert_true(not runner.has_active_game() and agent.pending_reload.is_empty(), "Real Pi testing never starts the live game or asks for reload approval")
    assert_true(not WorkspaceStoreScript.new().has_working_snapshot(created.name), "Standalone tests never promote working snapshot")
    agent.queue_free()
    runner.queue_free()
    await process_frame

func _test_real_pi_generation_edit_stream_and_restart() -> void:
    _settings("pi-gamesmith-e2e", 0.05, 150, 100000, 20000, "high")
    var created = _new_game("Pi E2E")
    assert_true(bool(created.get("ok", false)), "creates real-Pi e2e game")
    if not created.get("ok", false):
        return
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner, false)
    var tool_events: Array[String] = []
    var thought := {"text": ""}
    var streamed := {"text": ""}
    agent.llm_snippet.connect(func(kind, text):
        if kind == "tool": tool_events.append(str(text))
    )
    agent.llm_stream_delta.connect(func(kind, text):
        if kind == "thinking": thought.text += str(text)
        elif kind == "assistant": streamed.text += str(text)
    )

    agent.send_player_request("Build a tiny test game")
    var deadline = Time.get_ticks_msec() + 30000
    while agent.pending_reload.is_empty() and agent.busy and Time.get_ticks_msec() < deadline:
        await process_frame
    assert_true(not agent.pending_reload.is_empty(), "real Pi reload waits for player approval")
    for _frame in 8:
        await process_frame
    assert_true(agent.busy and not runner.has_active_game(), "waiting Pi stays busy without executing candidate")
    assert_true(FileAccess.file_exists(created.path.path_join("main.gd")), "Pi edits reach disk before reload approval")
    if agent.pending_reload.is_empty():
        agent.cancel()
        agent.queue_free()
        runner.queue_free()
        return
    agent.call_deferred("approve_reload")
    var ok = await agent.finished
    assert_true(bool(ok), "real supplied/global Pi completes initial generation")
    var main = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var speed := 200.0" in main, "Pi built-in write created main.gd")
    assert_true(runner.has_active_game(), "Pi custom reload_game round-tripped into GameRunner")
    var delivered_entries = await agent.rpc.command({"type": "get_entries"})
    assert_true(delivered_entries.get("data", {}).get("entries", []).any(func(entry): return entry.get("type", "") == "message" and entry.get("message", {}).get("toolName", "") == "reload_game" and "reload delivery integration marker" in JSON.stringify(entry)), "reload diagnostics are persisted in Pi's tool result")
    assert_true(runner.runtime_log.take_notification() == "", "persisted reload diagnostics are acknowledged at the session boundary")
    assert_true(tool_events.any(func(v): return "write" in v), "real Pi tool events reach GameSmith")
    assert_true(tool_events.any(func(v): return "reload_game" in v), "custom GameSmith tool event reaches UI stream")
    assert_true(str(streamed.text).contains("Built the initial"), "real Pi text deltas stream to GameSmith")
    assert_true(str(thought.text) != "", "provider-exposed Pi thinking deltas stream to GameSmith")
    var log = WorkspaceStoreScript.new().git.log(created.path, 5)
    assert_true("build initial Pi game" in str(log.get("output", "")), "Pi custom git_commit creates milestone")

    agent.send_player_request("make the player faster")
    deadline = Time.get_ticks_msec() + 30000
    while agent.pending_reload.is_empty() and agent.busy and Time.get_ticks_msec() < deadline:
        await process_frame
    assert_true(not agent.pending_reload.is_empty() and runner.has_active_game(), "each real Pi edit reload requires another approval")
    agent.call_deferred("approve_reload")
    ok = await agent.finished
    assert_true(bool(ok), "real Pi completes second edit turn")
    main = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var speed := 400.0" in main and not "var speed := 200.0" in main, "Pi built-in edit changes existing game safely")
    assert_true(str(streamed.text).contains("Player speed is now 400"), "second final response also streams")

    var state = await agent.rpc.command({"type": "get_state"})
    assert_true(bool(state.get("success", false)), "Pi RPC state is available")
    if bool(state.get("success", false)):
        assert_eq(str(state.get("data", {}).get("thinkingLevel", "")), "off", "unknown custom model does not receive unsupported reasoning settings")
    var before_entries = await agent.rpc.command({"type": "get_entries"})
    var before_json = JSON.stringify(before_entries.get("data", {}).get("entries", []))
    agent.restart_runtime()
    agent.queue_free()
    await process_frame

    var agent2 = _controller(created.name, created.path, runner)
    var ready = await agent2._ensure_runtime()
    assert_true(bool(ready.get("ok", false)), "new GameSmith controller resumes persisted Pi session")
    var after_entries = await agent2.rpc.command({"type": "get_entries"})
    assert_eq(JSON.stringify(after_entries.get("data", {}).get("entries", [])), before_json, "Pi session prefix is byte-stable across process restart before a new turn")
    agent2.send_player_request("what did I ask before?")
    ok = await agent2.finished
    assert_true(bool(ok), "resumed Pi session accepts another prompt")
    var transcript_text = FileAccess.get_file_as_string(MetadataStoreScript.new().transcript_path(created.name))
    assert_true("I remember both requests" in transcript_text and not "HISTORY_MISSING" in transcript_text, "provider sees prior Pi conversation after restart")

    var records = _fake_records("pi-gamesmith-e2e")
    assert_true(not records.is_empty(), "fake endpoint captured actual Pi requests")
    if not records.is_empty():
        var first: Dictionary = records[0]
        assert_eq(str(first.get("path", "")), "/v1/chat/completions", "custom base URL maps to Pi OpenAI-compatible endpoint")
        assert_eq(str(first.get("auth", "")), "Bearer pi-test-key", "custom API key is sent by Pi")
        var names: Array = first.get("tools", [])
        assert_true("read" in names and "edit" in names and "write" in names, "Pi built-in coding tools are exposed")
        assert_true("reload_game" in names and "git_commit" in names, "GameSmith extension tools are exposed")
        assert_true(not "bash" in names and not "powershell" in names, "shell tools are not exposed to the model")
    if records.size() >= 2:
        assert_true(int(records[1].get("time", 0)) - int(records[0].get("time", 0)) >= 35, "configured Pi inter-call delay is enforced between tool turns")

    agent2.restart_runtime()
    agent2.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _test_real_pi_completion_without_forced_tools() -> void:
    _settings("pi-gamesmith-no-action", 0.0)
    var created = _new_game("Pi No Action")
    if not created.get("ok", false):
        assert_true(false, "creates no-action game")
        return
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    agent.send_player_request("build a game")
    var ok = await agent.finished
    assert_true(bool(ok), "Pi may finish a change request without tools")
    assert_true(not FileAccess.file_exists(created.path.path_join("main.gd")), "host does not force creation of missing main.gd")
    assert_true(not runner.has_active_game(), "host does not force a reload on completion")
    assert_eq(_fake_records("pi-gamesmith-no-action").size(), 1, "no-action completion causes no automatic provider continuation")
    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

    _settings("pi-gamesmith-no-reload", 0.0)
    created = _new_game("Pi No Reload")
    if not created.get("ok", false):
        assert_true(false, "creates no-reload game")
        return
    _write(created.path.path_join("main.gd"), "extends Node\nvar answer = 1\n")
    runner = GameRunnerScript.new()
    root.add_child(runner)
    assert_true(runner.load_game(created.path).ok, "no-reload fixture has a running game")
    agent = _controller(created.name, created.path, runner)
    agent.send_player_request("change the answer to 2")
    ok = await agent.finished
    assert_true(bool(ok), "Pi may finish after editing without reloading")
    assert_true("answer = 2" in FileAccess.get_file_as_string(created.path.path_join("main.gd")), "Pi edit reaches workspace")
    assert_eq(runner.active_game.answer, 1, "host leaves running game untouched when Pi omits reload")
    assert_eq(_fake_records("pi-gamesmith-no-reload").size(), 2, "missing reload causes no automatic provider continuation")
    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _test_real_pi_retry_and_action_limit() -> void:
    _settings("pi-gamesmith-retry", 0.0)
    var created = _new_game("Pi Retry")
    if not created.get("ok", false):
        assert_true(false, "creates retry game")
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    agent.send_player_request("tell me if the provider recovers")
    var ok = await agent.finished
    assert_true(bool(ok), "Pi native retry recovers transient provider failure")
    var game_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(created.name))
    assert_true("pi.retry" in game_log, "Pi retry events are captured in GameSmith per-game logs")
    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

    _settings("pi-gamesmith-runaway", 0.0, 3)
    created = _new_game("Pi Runaway")
    if not created.get("ok", false):
        assert_true(false, "creates runaway game")
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    runner = GameRunnerScript.new()
    root.add_child(runner)
    agent = _controller(created.name, created.path, runner)
    agent.send_player_request("inspect forever")
    ok = await agent.finished
    assert_true(not bool(ok), "GameSmith aborts runaway Pi after configured action/turn limit")
    game_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(created.name))
    assert_true("turn limit" in game_log.to_lower(), "runaway Pi limit failure is logged")
    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _test_real_pi_cancel_and_rename() -> void:
    _settings("pi-gamesmith-cancel", 0.0, 150, 0)
    var created = _new_game("Pi Cancel Rename")
    assert_true(bool(created.get("ok", false)), "creates real Pi cancellation fixture")
    if not created.get("ok", false):
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    app._set_chat_visible(true)
    app.chat_input.text = "tell me something slowly"
    app._send_chat()
    # A test-only deadline keeps a broken cancellation regression from hanging CI.
    var deadline = Time.get_ticks_msec() + 30000
    while _fake_records("pi-gamesmith-cancel").is_empty() and Time.get_ticks_msec() < deadline:
        await process_frame
    assert_true(not _fake_records("pi-gamesmith-cancel").is_empty(), "real Pi reaches a deliberately stalled provider")
    app._stop_agent()
    assert_true(not app.agent.busy and app.chat_input.editable and not app.library_button.disabled, "Stop releases real Pi request and UI controls")
    deadline = Time.get_ticks_msec() + 5000
    while not _fake_records("pi-gamesmith-cancel").any(func(record): return record.get("event", "") == "cancelled-connection") and Time.get_ticks_msec() < deadline:
        await process_frame
    assert_true(_fake_records("pi-gamesmith-cancel").any(func(record): return record.get("event", "") == "cancelled-connection"), "Stop terminates the actual provider connection")
    app.runner.runtime_log.capture("error", "script_error", "Pi diagnostic integration marker")
    app.chat_input.text = "tell me if you can resume"
    app._send_chat()
    var ok = await app.agent.finished
    assert_true(bool(ok), "real Pi resumes its session after cancellation")
    var before = await app.agent.rpc.command({"type": "get_entries"})
    var entries: Array = before.get("data", {}).get("entries", [])
    assert_true(entries.any(func(entry): return entry.get("type", "") == "custom_message" and entry.get("customType", "") == "gamesmith-diagnostics" and not bool(entry.get("display", true))), "new diagnostic notice enters Pi as a hidden message")
    assert_true(entries.any(func(entry): return entry.get("type", "") == "message" and entry.get("message", {}).get("toolName", "") == "read_runtime_log" and "Pi diagnostic integration marker" in JSON.stringify(entry)), "real Pi filtered runtime-log tool receives durable diagnostic evidence")
    assert_true(app.runner.runtime_log.take_notification() == "", "delivered diagnostic notice is not announced again")
    app.rename_target = created.name
    var new_name = created.name + " Renamed"
    app.rename_edit.text = new_name
    app._rename_game()
    assert_eq(app.current_game, new_name, "renames a game with a real open Pi runtime")
    assert_true(app.agent.rpc == null, "rename retires real Pi runtime")
    var ready = await app.agent._ensure_runtime()
    assert_true(bool(ready.get("ok", false)), "renamed game starts Pi with new paths: " + str(ready.get("error", "")))
    if not bool(ready.get("ok", false)):
        app.queue_free()
        await process_frame
        return
    assert_true(str(app.agent.runtime_config.workspace).ends_with(new_name), "renamed Pi cwd uses new workspace")
    assert_true(str(app.agent.runtime_config.bridge_dir).contains(new_name), "renamed Pi bridge uses new metadata directory")
    var after = await app.agent.rpc.command({"type": "get_entries"})
    var old_messages: Array = before.get("data", {}).get("entries", []).filter(func(entry): return entry.get("type", "") == "message")
    var new_messages: Array = after.get("data", {}).get("entries", []).filter(func(entry): return entry.get("type", "") == "message")
    assert_eq(JSON.stringify(new_messages), JSON.stringify(old_messages), "rename preserves Pi conversation history")
    app.chat_input.text = "tell me something after rename"
    app._send_chat()
    ok = await app.agent.finished
    assert_true(bool(ok), "renamed real Pi session accepts another request")
    app.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(new_name)

func _test_real_pi_manual_and_auto_compaction() -> void:
    _settings("pi-gamesmith-compact-manual", 0.0, 150, 0, 1000)
    var created = _new_game("Pi Compact Manual")
    if not created.get("ok", false):
        assert_true(false, "creates manual Pi compaction game")
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    var small_noop = await agent.compact_now()
    assert_true(not bool(small_noop.get("ok", false)) and bool(small_noop.get("no_op", false)), "manual Pi compaction classifies an empty/small session as skipped, not failed")
    agent.send_player_request("remember this long context " + "x".repeat(6000))
    var ok = await agent.finished
    assert_true(bool(ok), "real Pi stores long context before manual compaction")
    agent.send_player_request("remember this second long context too " + "z".repeat(6000))
    ok = await agent.finished
    assert_true(bool(ok), "real Pi stores a second compactable user span")

    var pi_settings = JSON.parse_string(FileAccess.get_file_as_string(str(agent.runtime_config.agent_dir).path_join("settings.json")))
    assert_true(typeof(pi_settings) == TYPE_DICTIONARY and int(pi_settings.get("compaction", {}).get("keepRecentTokens", 0)) == 1000, "GameSmith keep-recent setting is passed to Pi unchanged")

    var compacted = await agent.compact_now()
    assert_true(bool(compacted.get("ok", false)), "GameSmith Compact now invokes Pi native compaction: %s" % str(compacted.get("error", "")))
    assert_true(str(compacted.get("summary", "")) != "", "Pi returns a real compaction summary: %s" % JSON.stringify(compacted))
    var entries = await agent.rpc.command({"type": "get_entries"})
    var manual_entries: Array = entries.get("data", {}).get("entries", [])
    assert_true(manual_entries.any(func(entry): return typeof(entry) == TYPE_DICTIONARY and str(entry.get("type", "")) == "compaction"), "Pi session persists a native compaction entry")

    var manual_entries_json = JSON.stringify(manual_entries)
    agent.restart_runtime()
    agent.queue_free()
    await process_frame
    var resumed = _controller(created.name, created.path, runner)
    var ready = await resumed._ensure_runtime()
    assert_true(bool(ready.get("ok", false)), "Pi session restarts after native compaction")
    var resumed_entries = await resumed.rpc.command({"type": "get_entries"})
    assert_eq(JSON.stringify(resumed_entries.get("data", {}).get("entries", [])), manual_entries_json, "compacted Pi session is byte-stable across GameSmith process restart")
    resumed.send_player_request("continue after manual compaction")
    ok = await resumed.finished
    assert_true(bool(ok), "resumed Pi session continues after manual compaction")
    var manual_transcript = FileAccess.get_file_as_string(MetadataStoreScript.new().transcript_path(created.name))
    assert_true("Continued from Pi's compacted session" in manual_transcript and not "COMPACTION_SUMMARY_MISSING" in manual_transcript, "provider receives native Pi checkpoint after manual compaction and restart")
    resumed.restart_runtime()
    resumed.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

    _settings("pi-gamesmith-compact-auto", 0.0, 150, 2000, 1000)
    created = _new_game("Pi Compact Auto")
    if not created.get("ok", false):
        assert_true(false, "creates automatic Pi compaction game")
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    runner = GameRunnerScript.new()
    root.add_child(runner)
    agent = _controller(created.name, created.path, runner)
    agent.send_player_request("remember automatic context one " + "y".repeat(6000))
    ok = await agent.finished
    assert_true(bool(ok), "first Pi request succeeds before automatic compaction has enough history")
    agent.send_player_request("remember automatic context two " + "w".repeat(6000))
    ok = await agent.finished
    assert_true(bool(ok), "second Pi request gives threshold maintenance a compactable older span")

    entries = await agent.rpc.command({"type": "get_entries"})
    var auto_entries: Array = entries.get("data", {}).get("entries", [])
    assert_true(auto_entries.any(func(entry): return typeof(entry) == TYPE_DICTIONARY and str(entry.get("type", "")) == "compaction"), "configured GameSmith token threshold triggers a real Pi compaction entry")

    var records_before_continue = _fake_records("pi-gamesmith-compact-auto").size()
    agent.send_player_request("continue after compaction")
    ok = await agent.finished
    assert_true(bool(ok), "Pi continues after threshold compaction")
    var transcript_text = FileAccess.get_file_as_string(MetadataStoreScript.new().transcript_path(created.name))
    assert_true("Continued from Pi's compacted session" in transcript_text and not "COMPACTION_SUMMARY_MISSING" in transcript_text, "next provider request receives Pi's compacted session context")
    var records_after_continue = _fake_records("pi-gamesmith-compact-auto")
    assert_true(records_after_continue.size() > records_before_continue, "fake endpoint captured provider request after compaction")
    var saw_checkpoint_request = false
    for i in range(records_before_continue, records_after_continue.size()):
        var record: Dictionary = records_after_continue[i]
        if (record.get("tools", []) as Array).is_empty():
            continue
        var rendered = JSON.stringify(record.get("messages", []))
        if "The conversation history before this point was compacted" in rendered or "## Goal" in rendered:
            saw_checkpoint_request = true
    assert_true(saw_checkpoint_request, "post-compaction normal provider request carries Pi checkpoint context")

    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)


func _test_legacy_transcript_import_is_one_time() -> void:
    _settings("pi-gamesmith-legacy-import", 0.0, 150, 0, 1000)
    var created = _new_game("Pi Legacy Import")
    assert_true(bool(created.get("ok", false)), "creates legacy-transcript migration game")
    if not created.get("ok", false):
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    var readable = TranscriptStoreScript.new()
    readable.append(created.name, "user", "Build a blue square")
    readable.append(created.name, "assistant", "Built the blue square.")
    var legacy_before = readable.read_all(created.name, 100)
    assert_eq(legacy_before.size(), 2, "legacy readable transcript fixture starts with exactly two entries")

    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    agent.send_player_request("What did we build?")
    var ok = await agent.finished
    assert_true(bool(ok), "first Pi turn after legacy migration succeeds")

    var records = _fake_records("pi-gamesmith-legacy-import")
    assert_true(not records.is_empty(), "fake provider captured first request after legacy migration")
    if not records.is_empty():
        var rendered = JSON.stringify(records[0].get("messages", []))
        assert_true("Build a blue square" in rendered and "Built the blue square." in rendered, "legacy readable dialogue is visible to the first Pi provider request")
        assert_eq(rendered.split("What did we build?").size() - 1, 1, "current player request appears exactly once and is not re-imported as legacy history")

    var after_turn = readable.read_all(created.name, 100)
    assert_eq(after_turn.size(), 4, "migration leaves readable transcript human-owned and only appends the new turn")
    if after_turn.size() >= 4:
        assert_eq(str(after_turn[0].get("content", "")), "Build a blue square", "legacy readable user entry remains unchanged")
        assert_eq(str(after_turn[1].get("content", "")), "Built the blue square.", "legacy readable assistant entry remains unchanged")
        assert_eq(str(after_turn[2].get("content", "")), "What did we build?", "new user turn is appended after imported legacy dialogue")

    var entries = await agent.rpc.command({"type": "get_entries"})
    var before_restart_json = JSON.stringify(entries.get("data", {}).get("entries", []))
    assert_eq(before_restart_json.split("gamesmith-legacy-dialogue").size() - 1, 1, "Pi persists exactly one legacy-import checkpoint entry")

    agent.restart_runtime()
    agent.queue_free()
    await process_frame
    var resumed = _controller(created.name, created.path, runner)
    var ready = await resumed._ensure_runtime()
    assert_true(bool(ready.get("ok", false)), "Pi session with imported legacy dialogue restarts")
    var resumed_entries = await resumed.rpc.command({"type": "get_entries"})
    assert_eq(JSON.stringify(resumed_entries.get("data", {}).get("entries", [])), before_restart_json, "restart does not import readable transcript a second time")

    resumed.restart_runtime()
    resumed.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

func _test_legacy_runtime_sources_are_removed() -> void:
    for path in [
        "res://src/agent/agent_controller.gd",
        "res://src/core/conversation_store.gd",
        "res://src/core/compaction_service.gd",
        "res://src/providers/provider_factory.gd",
        "res://src/providers/openai_compatible_provider.gd"
    ]:
        assert_true(not FileAccess.file_exists(path), "obsolete homegrown runtime source is deleted: %s" % path)
    var app_source = FileAccess.get_file_as_string("res://src/ui/app.gd")
    var runtime_source = FileAccess.get_file_as_string("res://src/pi/pi_runtime_config.gd")
    assert_true(not "res://src/providers/" in app_source, "production UI no longer preloads legacy provider adapters")
    assert_true(not "res://src/providers/" in runtime_source, "Pi runtime config no longer preloads legacy provider adapters")


func _test_pi_binary_discovery_modes() -> void:
    var explicit = OS.get_environment("GAMESMITH_PI_BIN").strip_edges()
    assert_true(explicit != "", "Part 4 receives an explicit Pi executable fixture")
    var session = PiRpcSessionScript.new()
    var explicit_result = session._check_pi_available()
    assert_true(bool(explicit_result.get("ok", false)), "explicit GAMESMITH_PI_BIN override resolves")

    OS.unset_environment("GAMESMITH_PI_BIN")
    var global_result = session._check_pi_available()
    assert_true(bool(global_result.get("ok", false)), "globally npm-installed pi resolves from PATH without override: %s" % str(global_result.get("error", "")))
    OS.set_environment("GAMESMITH_PI_BIN", explicit)
    session.free()

func _test_windows_pi_install_guidance() -> void:
    var readme = FileAccess.get_file_as_string("res://GameSmith-Windows/README.txt")
    assert_true("npm install -g @earendil-works/pi-coding-agent@1.0.0" in readme, "Windows README gives the pinned global Pi install command")
    assert_true("GAMESMITH_PI_BIN" in readme, "Windows README documents the explicit Pi executable override")

func _fake_records(model: String) -> Array:
    var out: Array = []
    if fake_log == "" or not FileAccess.file_exists(fake_log):
        return out
    var file = FileAccess.open(fake_log, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line = file.get_line().strip_edges()
        if line == "":
            continue
        var parsed = JSON.parse_string(line)
        if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("model", "")) == model:
            out.append(parsed)
    return out

func _write(path: String, content: String) -> void:
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_string(content)
        f.close()
