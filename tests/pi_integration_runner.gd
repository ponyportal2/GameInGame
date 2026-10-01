extends SceneTree

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")

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
    assert_true(base_url != "", "Pi integration receives fake OpenAI-compatible base URL")
    assert_true(OS.get_environment("GAMESMITH_PI_BIN") != "", "Pi integration receives explicit globally-installed Pi command for CI")
    await _test_production_app_uses_pi()
    await _test_real_pi_generation_edit_stream_and_restart()
    await _test_real_pi_false_done_verifier()
    await _test_real_pi_retry_and_action_limit()
    await _test_real_pi_manual_and_auto_compaction()
    print("PI INTEGRATION TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

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

func _controller(game_name: String, path: String, runner: Node) -> Node:
    var agent = PiAgentControllerScript.new()
    root.add_child(agent)
    agent.configure(game_name, GameToolsScript.new(path, runner))
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

func _test_real_pi_generation_edit_stream_and_restart() -> void:
    _settings("pi-gamesmith-e2e", 0.05, 150, 100000, 20000, "high")
    var created = _new_game("Pi E2E")
    assert_true(bool(created.get("ok", false)), "creates real-Pi e2e game")
    if not created.get("ok", false):
        return
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    var tool_events: Array[String] = []
    var thought := ""
    var streamed := ""
    agent.llm_snippet.connect(func(kind, text):
        if kind == "tool": tool_events.append(str(text))
    )
    agent.llm_stream_delta.connect(func(kind, text):
        if kind == "thinking": thought += str(text)
        elif kind == "assistant": streamed += str(text)
    )

    agent.send_player_request("Build a tiny test game")
    var ok = await agent.finished
    assert_true(bool(ok), "real supplied/global Pi completes initial generation")
    var main = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var speed := 200.0" in main, "Pi built-in write created main.gd")
    assert_true(runner.has_active_game(), "Pi custom reload_game round-tripped into GameRunner")
    assert_true(tool_events.any(func(v): return "write" in v), "real Pi tool events reach GameSmith")
    assert_true(tool_events.any(func(v): return "reload_game" in v), "custom GameSmith tool event reaches UI stream")
    assert_true(streamed.contains("Built the initial"), "real Pi text deltas stream to GameSmith")
    assert_true(thought != "", "provider-exposed Pi thinking deltas stream to GameSmith")
    var log = WorkspaceStoreScript.new().git.log(created.path, 5)
    assert_true("build initial Pi game" in str(log.get("output", "")), "Pi custom git_commit creates milestone")

    agent.send_player_request("make the player faster")
    ok = await agent.finished
    assert_true(bool(ok), "real Pi completes second edit turn")
    main = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var speed := 400.0" in main and not "var speed := 200.0" in main, "Pi built-in edit changes existing game safely")
    assert_true(streamed.contains("Player speed is now 400"), "second final response also streams")

    var state = await agent.rpc.command({"type": "get_state"}, 15.0)
    assert_true(bool(state.get("success", false)), "Pi RPC state is available")
    if bool(state.get("success", false)):
        assert_eq(str(state.get("data", {}).get("thinkingLevel", "")), "high", "GameSmith reasoning setting maps to Pi thinking level")
    var before_entries = await agent.rpc.command({"type": "get_entries"}, 15.0)
    var before_json = JSON.stringify(before_entries.get("data", {}).get("entries", []))
    agent.restart_runtime()
    agent.queue_free()
    await process_frame

    var agent2 = _controller(created.name, created.path, runner)
    var ready = await agent2._ensure_runtime()
    assert_true(bool(ready.get("ok", false)), "new GameSmith controller resumes persisted Pi session")
    var after_entries = await agent2.rpc.command({"type": "get_entries"}, 15.0)
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

func _test_real_pi_false_done_verifier() -> void:
    _settings("pi-gamesmith-false-done", 0.0)
    var created = _new_game("Pi False Done")
    if not created.get("ok", false):
        assert_true(false, "creates false-Done game")
        return
    var runner = GameRunnerScript.new()
    root.add_child(runner)
    var agent = _controller(created.name, created.path, runner)
    agent.send_player_request("build a game")
    var ok = await agent.finished
    assert_true(bool(ok), "Pi settlement hook recovers from false Done")
    assert_true(FileAccess.file_exists(created.path.path_join("main.gd")), "false-Done continuation actually creates main.gd")
    assert_true(runner.has_active_game(), "false-Done continuation successfully reloads game")
    var records = _fake_records("pi-gamesmith-false-done")
    assert_true(records.size() >= 4, "false-Done completion causes another Pi provider turn")
    if records.size() >= 2:
        assert_true("GameSmith verification rejected completion" in JSON.stringify(records[1].get("messages", [])), "Pi continuation receives hidden GameSmith verifier context without a player message")
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
    agent.send_player_request("remember this long context " + "x".repeat(6000))
    var ok = await agent.finished
    assert_true(bool(ok), "real Pi stores long context before manual compaction")
    agent.send_player_request("add a second context span " + "z".repeat(3000))
    ok = await agent.finished
    assert_true(bool(ok), "real Pi stores a second user span so manual compaction has an older span to summarize")
    var compacted = await agent.compact_now()
    assert_true(bool(compacted.get("ok", false)), "GameSmith Compact now invokes Pi native compaction")
    assert_true(str(compacted.get("summary", "")) != "", "Pi returns a real compaction summary")
    var entries = await agent.rpc.command({"type": "get_entries"}, 15.0)
    assert_true("compaction" in JSON.stringify(entries.get("data", {}).get("entries", [])), "Pi session persists a native compaction entry")
    agent.restart_runtime()
    agent.queue_free()
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
    agent.send_player_request("store context before automatic compaction " + "y".repeat(5000))
    ok = await agent.finished
    assert_true(bool(ok), "normal Pi request succeeds before automatic threshold maintenance")
    entries = await agent.rpc.command({"type": "get_entries"}, 15.0)
    assert_true("compaction" in JSON.stringify(entries.get("data", {}).get("entries", [])), "configured GameSmith token threshold triggers Pi native compaction")
    agent.send_player_request("continue after compaction")
    ok = await agent.finished
    assert_true(bool(ok), "Pi continues after threshold compaction")
    var transcript_text = FileAccess.get_file_as_string(MetadataStoreScript.new().transcript_path(created.name))
    assert_true("Continued from Pi's compacted session" in transcript_text and not "COMPACTION_SUMMARY_MISSING" in transcript_text, "next provider request receives Pi's compacted session context")
    agent.restart_runtime()
    agent.queue_free()
    runner.queue_free()
    await process_frame
    WorkspaceStoreScript.new().delete_game(created.name)

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
