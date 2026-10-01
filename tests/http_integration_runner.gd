extends SceneTree

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const AgentControllerScript = preload("res://src/agent/agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const ConversationStoreScript = preload("res://src/core/conversation_store.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")

var failures = 0
var passed = 0
var base_url = ""

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
    base_url = OS.get_environment("GAMESMITH_FAKE_BASE")
    if base_url == "":
        push_error("GAMESMITH_FAKE_BASE is required")
        quit(2)
        return
    await _test_real_http_ui_send_flow()
    await _test_real_http_create_edit_and_repair()
    await _test_real_http_malformed_and_provider_failures()
    await _test_real_http_transport_timeout_diagnostics()
    await _test_real_http_auto_compaction()
    await _test_legacy_verifier_history_cleanup()
    print("HTTP TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

func _settings(model: String, reasoning: String = "") -> void:
    var meta = MetadataStoreScript.new()
    meta.ensure()
    var settings = meta.global_settings().duplicate(true)
    settings.provider = "custom"
    settings.model = model
    settings.custom_base_url = base_url
    settings.reasoning_effort = reasoning
    settings.llm_call_delay_sec = 0.0
    assert_true(meta.save_global_settings(settings), "saves custom-provider HTTP test settings for " + model)

func _send(name: String, path: String, runner, text: String, model: String, reasoning: String = "") -> Dictionary:
    _settings(model, reasoning)
    var agent = AgentControllerScript.new()
    root.add_child(agent)
    agent.configure(name, GameToolsScript.new(path, runner))
    agent.send_player_request(text)
    var ok = await agent.finished
    agent.queue_free()
    await process_frame
    return {"ok": ok}

func _test_real_http_ui_send_flow() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "HTTP UI Flow"
    if name in store.list_games(): store.delete_game(name)
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "UI HTTP flow creates empty game from normal workspace path")
    if not created.get("ok", false): return
    _settings("gamesmith-ui-create", "high")
    var packed = load("res://main.tscn")
    var app = packed.instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    assert_true(app.chat_overlay.visible, "opening an empty game shows the real chat overlay")
    app.chat_input.text = "create a simple tetris 3d game"
    app.chat_input.grab_focus()
    await process_frame
    var enter = InputEventKey.new(); enter.keycode = KEY_ENTER; enter.physical_keycode = KEY_ENTER; enter.pressed = true
    Input.parse_input_event(enter)
    var ok = await app.agent.finished
    assert_true(bool(ok), "real UI send path completes through production HTTP provider")
    assert_true(FileAccess.file_exists(created.path.path_join("main.gd")), "real UI send path leaves generated source in the game folder")
    assert_true(app.runner.has_active_game(), "real UI send path leaves a running generated game")
    assert_true(app.chat_input.editable, "real UI send path re-enables composer after completion")
    var ui_text = app.transcript_view.get_parsed_text()
    assert_true("Built and loaded the 3D falling-block game." in ui_text, "real UI transcript renders verified completion")
    var entries = TranscriptStoreScript.new().read_all(name)
    assert_eq(entries.size(), 2, "real UI transcript does not persist premature Done as success")
    var provider_history = ConversationStoreScript.new().read_all(name)
    var verifier_pollution = false
    for message in provider_history:
        if str(message.get("role", "")) == "system" and str(message.get("content", "")).begins_with("GameSmith verification rejected that completion:"):
            verifier_pollution = true
    assert_true(not verifier_pollution, "rejected verifier nudges stay ephemeral instead of polluting durable provider history")
    var debug_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(name))
    assert_true("agent.request" in debug_log and "agent.tool" in debug_log and "agent.finished" in debug_log, "real HTTP UI flow writes actionable per-game debug lifecycle")
    app.queue_free(); paused = false; await process_frame
    store.delete_game(name)

func _test_real_http_create_edit_and_repair() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "HTTP Agent E2E"
    if name in store.list_games(): store.delete_game(name)
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "HTTP E2E creates a real Git workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)

    var create_result = await _send(name, created.path, runner, "create a simple tetris 3d game", "gamesmith-noop-create", "high")
    assert_true(bool(create_result.ok), "real HTTP agent recovers from a text-only Done on a new game")
    assert_true(FileAccess.file_exists(created.path.path_join("main.gd")), "real HTTP tool call writes main.gd")
    assert_true(runner.has_active_game(), "real HTTP tool call reloads and instantiates generated game")
    if runner.has_active_game():
        assert_true(runner.active_game is Node3D, "HTTP-generated game is a live 3D root")
        assert_eq(runner.active_game.fall_speed, 1.0, "HTTP-generated game exposes expected initial behavior")
        var before = runner.active_game.block.position.y
        await process_frame; await process_frame
        assert_true(runner.active_game.block.position.y < before, "HTTP-generated 3D game actually processes frames")
    var visible = TranscriptStoreScript.new().read_all(name)
    assert_eq(visible.size(), 2, "premature HTTP Done is not exposed as a successful assistant transcript entry")
    if visible.size() >= 2:
        assert_eq(str(visible[-1].content), "Built and loaded the 3D falling-block game.", "HTTP transcript ends with verified completion")

    var edit_result = await _send(name, created.path, runner, "make the blocks fall faster", "gamesmith-edit-speed")
    assert_true(bool(edit_result.ok), "real HTTP edit continues after premature post-edit Done")
    assert_true(runner.has_active_game(), "edited game remains active")
    if runner.has_active_game(): assert_eq(runner.active_game.fall_speed, 3.0, "real HTTP edit is active only after required reload")
    var source = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var fall_speed = 3.0" in source, "real HTTP patch persists in workspace")
    var log: Dictionary = store.git.log(created.path, 8)
    assert_true("Increase fall speed" in str(log.get("output", "")) and "Create fake-endpoint 3D game" in str(log.get("output", "")), "real HTTP flow creates coherent Git milestones")

    var repair_result = await _send(name, created.path, runner, "fix the game after a bad reload", "gamesmith-reload-repair")
    assert_true(bool(repair_result.ok), "real HTTP agent repairs a failed candidate instead of accepting Done")
    assert_true(runner.has_active_game(), "repaired HTTP game is active")
    if runner.has_active_game(): assert_eq(runner.active_game.fall_speed, 4.0, "repaired HTTP candidate is the running version")

    runner.queue_free(); await process_frame
    store.delete_game(name)


func _test_real_http_transport_timeout_diagnostics() -> void:
    var provider = OpenAICompatibleProvider.new(root, base_url + "/chat/completions", "", "gamesmith-timeout", PackedStringArray(), "", false)
    provider.request_timeout_sec = 0.05
    var result: Dictionary = await provider.complete([{"role": "user", "content": "hello"}], [])
    assert_true(not bool(result.get("ok", true)), "real HTTP delayed provider hits transport timeout")
    assert_true("timed out" in str(result.get("error", "")).to_lower(), "transport timeout is named instead of reported as HTTP 0")
    var diagnostics: Dictionary = result.get("diagnostics", {})
    assert_eq(str(diagnostics.get("transport", "")), "timeout", "transport diagnostics identify timeout")
    assert_eq(int(diagnostics.get("http_status", -1)), 0, "transport diagnostics retain HTTP 0 only as secondary status")
    assert_true(int(diagnostics.get("elapsed_ms", 0)) > 0, "transport diagnostics include elapsed time")
    assert_true(str(diagnostics.get("endpoint", "")).ends_with("/v1/chat/completions"), "transport diagnostics include sanitized endpoint")

func _test_real_http_auto_compaction() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "HTTP Auto Compaction"
    if name in store.list_games(): store.delete_game(name)
    var created = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates real-HTTP compaction workspace")
    if not created.get("ok", false): return

    var conv = ConversationStoreScript.new()
    for i in 12:
        conv.append(name, {"role": "user", "content": "old-http-%d %s" % [i, "h".repeat(1600)]})
        conv.append(name, {"role": "assistant", "content": "old-http-answer-%d" % i})

    _settings("gamesmith-auto-compact")
    var meta = MetadataStoreScript.new()
    var settings = meta.global_settings().duplicate(true)
    settings.compaction_auto_tokens = 5000
    settings.compaction_keep_recent_tokens = 1000
    settings.llm_call_delay_sec = 0.0
    meta.save_global_settings(settings)

    var runner = GameRunnerScript.new(); root.add_child(runner)
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner))
    agent.send_player_request("tell me the current status")
    var ok = await agent.finished
    assert_true(bool(ok), "real HTTP auto-compaction summarizes then continues normal agent request")
    var entries = conv.read_entries(name)
    var checkpoint_count = 0
    for entry in entries:
        if str(entry.get("type", "")) == "compaction":
            checkpoint_count += 1
    assert_true(checkpoint_count >= 1, "real HTTP auto-compaction persists a checkpoint marker")
    var provider_context = conv.read_for_provider(name)
    assert_true(not provider_context.is_empty() and "The conversation history before this point was compacted into the following summary:" in str(provider_context[0].get("content", "")), "real HTTP replay begins with Pi checkpoint wrapper")

    settings.compaction_auto_tokens = 100000
    settings.compaction_keep_recent_tokens = 20000
    meta.save_global_settings(settings)
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)


func _test_legacy_verifier_history_cleanup() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "HTTP Legacy History Cleanup"
    if name in store.list_games(): store.delete_game(name)
    var created = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates legacy verifier-history workspace")
    if not created.get("ok", false): return
    var conversation = ConversationStoreScript.new()
    conversation.append(name, {"role": "user", "content": "make it better"})
    conversation.append(name, {"role": "assistant", "content": "Done."})
    conversation.append(name, {"role": "system", "content": "GameSmith verification rejected that completion: simulated old persisted verifier message"})
    var cleaned = conversation.read_for_provider(name)
    assert_true(cleaned.size() == 1 and str(cleaned[0].get("role", "")) == "user", "legacy verifier correction and rejected assistant response are filtered from provider replay")
    assert_true(conversation.needs_recovery_marker(cleaned), "unfinished cleaned history is detected for recovery")
    _settings("gamesmith-history-cleanup")
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner))
    agent.send_player_request("continue")
    var ok = await agent.finished
    assert_true(bool(ok), "real HTTP provider accepts cleaned history plus recovery marker")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_real_http_malformed_and_provider_failures() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()

    var malformed_name = "HTTP Malformed"
    if malformed_name in store.list_games(): store.delete_game(malformed_name)
    var malformed = store.create_game(malformed_name)
    assert_true(bool(malformed.get("ok", false)), "creates HTTP malformed-tool workspace")
    if malformed.get("ok", false):
        var runner = GameRunnerScript.new(); root.add_child(runner)
        var before_log = str(store.git.log(malformed.path, 5).get("output", ""))
        var malformed_result = await _send(malformed_name, malformed.path, runner, "Test malformed tool arguments", "gamesmith-malformed-tool")
        assert_true(bool(malformed_result.ok), "real HTTP malformed tool arguments are surfaced back to model and recover")
        var after_log = str(store.git.log(malformed.path, 5).get("output", ""))
        assert_eq(after_log, before_log, "malformed HTTP git_commit never executes with fallback arguments")
        runner.queue_free(); await process_frame
        store.delete_game(malformed_name)

    for case in [
        {"name": "HTTP 500", "model": "gamesmith-http-500", "needle": "HTTP 500"},
        {"name": "HTTP Invalid JSON", "model": "gamesmith-invalid-json", "needle": "unexpected response"},
    ]:
        var created = store.create_game(case.name)
        assert_true(bool(created.get("ok", false)), "creates provider failure workspace " + case.name)
        if not created.get("ok", false): continue
        var runner = GameRunnerScript.new(); root.add_child(runner)
        var result = await _send(case.name, created.path, runner, "Tell me provider status", case.model)
        assert_true(not bool(result.ok), case.name + " fails the agent request cleanly")
        var transcript = TranscriptStoreScript.new().read_all(case.name)
        assert_true(not transcript.is_empty() and case.needle.to_lower() in str(transcript[-1].content).to_lower(), case.name + " records useful provider failure text")
        assert_true(not runner.has_active_game(), case.name + " cannot fabricate a running game")
        var debug_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(case.name))
        assert_true("provider.error" in debug_log and "agent.failed" in debug_log, case.name + " writes provider failure details to per-game debug log")
        runner.queue_free(); await process_frame
        store.delete_game(case.name)

    var limit_name = "HTTP Step Limit"
    var limit = store.create_game(limit_name)
    assert_true(bool(limit.get("ok", false)), "creates HTTP step-limit workspace")
    if limit.get("ok", false):
        # The default=150 contract is covered by the fast/UI tests. Keep this real-HTTP
        # failure-path test intentionally small so the acceptance workflow stays cheap.
        var meta = MetadataStoreScript.new()
        var original_settings = meta.global_settings().duplicate(true)
        var limited_settings = original_settings.duplicate(true)
        limited_settings.max_agent_steps = 3
        meta.save_global_settings(limited_settings)
        var runner = GameRunnerScript.new(); root.add_child(runner)
        var result = await _send(limit_name, limit.path, runner, "Keep checking forever", "gamesmith-step-limit")
        assert_true(not bool(result.ok), "real HTTP repeated tool calls hit deterministic step limit")
        var transcript = TranscriptStoreScript.new().read_all(limit_name)
        assert_true(not transcript.is_empty() and "step limit" in str(transcript[-1].content).to_lower(), "real HTTP step-limit failure is readable")
        meta.save_global_settings(original_settings)
        runner.queue_free(); await process_frame
        store.delete_game(limit_name)
