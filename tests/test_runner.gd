extends SceneTree

const PathUtilsScript = preload("res://src/core/path_utils.gd")
const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const PiProviderCatalogScript = preload("res://src/pi/pi_provider_catalog.gd")
const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")
const ThemeFactoryScript = preload("res://src/ui/theme_factory.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const LegacyDataMigratorScript = preload("res://src/core/legacy_data_migrator.gd")

var failures = 0
var passed = 0

class FakeUiAgent:
    extends Node
    signal status_changed(text: String)
    signal assistant_message(text: String)
    signal llm_snippet(kind: String, text: String)
    signal llm_stream_delta(kind: String, text: String)
    signal llm_stream_end(kind: String)
    signal finished(ok: bool)

    var tree: SceneTree
    var game_name := ""
    var transcript = TranscriptStoreScript.new()
    var busy := false
    var call_count := 0
    var send_mode := "simple"
    var compact_result: Dictionary = {"ok": true, "tokens_before": 9000, "tokens_after": 1200}
    var compact_frames := 2

    func _init(p_tree: SceneTree):
        tree = p_tree

    func configure(p_game_name: String, _tools) -> void:
        game_name = p_game_name

    func send_player_request(text: String) -> void:
        if busy: return
        busy = true
        transcript.append(game_name, "user", text)
        call_count += 1
        status_changed.emit("Fake UI agent working…")
        call_deferred("_finish_send")

    func _finish_send() -> void:
        await tree.process_frame
        if send_mode == "snippets":
            llm_snippet.emit("thinking", "I should inspect the workspace files before answering…")
            llm_snippet.emit("assistant", "Let me check the current files first so I can answer…")
            llm_snippet.emit("tool", "search_text {\"query\":\"find the player speed consta…")
            transcript.append(game_name, "assistant", "All done.")
            assistant_message.emit("All done.")
        else:
            transcript.append(game_name, "assistant", "Hi.")
            assistant_message.emit("Hi.")
        busy = false
        status_changed.emit("Ready")
        finished.emit(true)

    func compact_now() -> Dictionary:
        if busy:
            return {"ok": false, "error": "Agent is busy."}
        busy = true
        for _i in compact_frames:
            await tree.process_frame
        busy = false
        return compact_result.duplicate(true)

    func context_tokens() -> int:
        return 9000

    func settings_changed() -> void:
        pass


func _init() -> void:
    call_deferred("run")

func assert_true(value: bool, label: String) -> void:
    if value:
        passed += 1; print("PASS: ", label)
    else:
        failures += 1; push_error("FAIL: " + label)

func assert_eq(actual, expected, label: String) -> void:
    assert_true(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])

func run() -> void:
    await _test_paths()
    await _test_workspace_and_git()
    await _test_rename_metadata_and_snapshot()
    await _test_tool_boundary()
    await _test_large_file_read_and_patch_integrity()
    await _test_runner_multifile_and_failed_candidate()
    await _test_app_identity_settings_and_compact_ui()
    _set_test_llm_call_delay(0.0)
    await _test_chat_pause_keeps_host_alive()
    await _test_chat_owns_mouse_mode_across_generated_reload()
    await _test_enter_sends_chat_message()
    await _test_llm_snippets_reach_chat()
    await _test_chat_escapes_bbcode()
    await _test_library_is_blocked_while_agent_works()
    await _test_manual_compaction_chat_feedback_and_send_guard()
    await _test_legacy_user_data_migration()
    await _test_debug_logs_and_redaction()
    await _test_provider_settings_surface()
    await _test_pi_request_has_no_host_deadline_or_fake_completion()
    await _test_stale_pi_settlement_does_not_finish_next_request()
    print("TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

func _replace_app_agent(app, fake: FakeUiAgent) -> void:
    if is_instance_valid(app.agent):
        app.agent.queue_free()
    app.agent = fake
    app.add_child(fake)
    fake.configure(app.current_game, app.tools)
    fake.status_changed.connect(func(text): app.status_label.text = text)
    fake.assistant_message.connect(func(text): app._append_chat("assistant", text))
    fake.llm_snippet.connect(func(kind, text): app._append_chat(kind, text))
    fake.llm_stream_delta.connect(app._append_stream_delta)
    fake.llm_stream_end.connect(app._end_stream_block)
    fake.finished.connect(app._on_agent_finished)


func _test_paths() -> void:
    assert_eq(PathUtilsScript.sanitize_game_name("  My / Game:*  "), "My Game", "sanitizes folder name")
    assert_eq(PathUtilsScript.safe_relative_path("scripts/player.gd"), "scripts/player.gd", "accepts safe relative path")
    assert_eq(PathUtilsScript.safe_relative_path("../host/credentials.json"), "", "rejects traversal")
    assert_eq(PathUtilsScript.safe_relative_path("/etc/passwd"), "", "rejects absolute path")

func _test_workspace_and_git() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Test Workspace %d" % Time.get_ticks_msec()
    var created = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates game workspace")
    if created.get("ok", false):
        assert_true(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(created.path.path_join(".git"))), "initializes git repository")
        var log: Dictionary = store.git.log(created.path, 3)
        assert_true(bool(log.get("ok", false)) and "Initialize game" in str(log.get("output", "")), "creates baseline commit")
        assert_true(not FileAccess.file_exists(created.path.path_join("main.gd")), "new workspace has no scaffold")
        _write(created.path.path_join("main.gd"), "extends Node\n")
        assert_true(store._remove_tree(created.path.path_join(".git")), "test fixture can remove Git metadata")
        var recovered = store.ensure_game_repo(created.name)
        assert_true(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)), "opening an existing workspace can recover missing Git metadata")
        var recovered_log: Dictionary = store.git.log(created.path, 3)
        assert_true("Initialize existing game" in str(recovered_log.get("output", "")), "Git recovery captures current workspace as a baseline commit")
        store.delete_game(created.name)

func _test_rename_metadata_and_snapshot() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var old_name = "Rename Test %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(old_name)
    assert_true(bool(created.get("ok", false)), "creates rename test workspace")
    if not created.get("ok", false): return
    var main_path = created.path.path_join("main.gd")
    _write(main_path, "extends Node\n")
    assert_true(store.save_working_snapshot(old_name), "stores last-working snapshot outside workspace")
    var new_name = old_name + " Renamed"
    var renamed: Dictionary = store.rename_game(old_name, new_name)
    assert_true(bool(renamed.get("ok", false)), "renames workspace and metadata")
    assert_true(FileAccess.file_exists(store.metadata.snapshot_dir(new_name).path_join("main.gd")), "working snapshot migrates with metadata")
    assert_true(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store.metadata.game_meta_dir(old_name))), "old metadata key is removed")
    store.delete_game(new_name)

func _test_tool_boundary() -> void:
    var root = "user://games/tool-boundary-test"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
    var tools = GameToolsScript.new()
    tools.workspace = root
    assert_true(not tools.read_file("../host/credentials.json").ok, "tool cannot escape workspace")
    assert_true(tools.write_file("main.gd", "extends Node\n").ok, "tool writes inside workspace")
    var meta = MetadataStoreScript.new(); meta._remove_tree_abs(ProjectSettings.globalize_path(root))

func _test_large_file_read_and_patch_integrity() -> void:
    var root_dir = "user://games/large-file-tool-test"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_dir))
    var tools = GameToolsScript.new(root_dir)
    var large = ""
    for i in 800:
        if i == 10:
            large += "var TARGET_TOKEN = 1\n"
        else:
            large += "line_%04d = \"%s\"\n" % [i, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]
    large += "TAIL_SENTINEL\n"
    _write(root_dir.path_join("large.gd"), large)
    assert_true(large.to_utf8_buffer().size() > 30000, "large-file regression fixture exceeds old 30 KB read cap")

    var head = tools.execute("read_file", {"path": "large.gd", "offset": 1, "limit": 25})
    assert_true(bool(head.get("ok", false)), "chunked read succeeds")
    assert_true(bool(head.get("truncated", false)), "chunked read explicitly reports that more file content exists")
    assert_eq(int(head.get("line_start", 0)), 1, "chunked read reports first returned line")
    assert_eq(int(head.get("line_end", 0)), 25, "chunked read respects requested line limit")
    assert_eq(int(head.get("next_offset", 0)), 26, "chunked read exposes continuation offset")

    var tail = tools.execute("read_file", {"path": "large.gd", "offset": 790, "limit": 30})
    assert_true("TAIL_SENTINEL" in str(tail.get("content", "")), "chunked read can retrieve the tail of a large file")

    var before = FileAccess.get_file_as_string(root_dir.path_join("large.gd"))
    var patched = tools.patch_file("large.gd", "var TARGET_TOKEN = 1", "var TARGET_TOKEN = 2")
    var after = FileAccess.get_file_as_string(root_dir.path_join("large.gd"))
    assert_true(bool(patched.get("ok", false)), "patch_file accepts an exact unique edit in a large file")
    assert_true("var TARGET_TOKEN = 2" in after, "patch_file applies requested edit")
    assert_true("TAIL_SENTINEL" in after, "patch_file preserves content beyond the read preview window")
    assert_eq(after.length(), before.length(), "equal-length patch preserves the complete file length")
    assert_eq(int(patched.get("bytes_before", -1)), before.to_utf8_buffer().size(), "patch result reports original full-file size")
    assert_eq(int(patched.get("bytes_after", -1)), after.to_utf8_buffer().size(), "patch result reports resulting full-file size")

    var meta = MetadataStoreScript.new()
    meta._remove_tree_abs(ProjectSettings.globalize_path(root_dir))


func _test_runner_multifile_and_failed_candidate() -> void:
    var dir = "user://games/runtime-test"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    _write(dir.path_join("helper.gd"), "extends RefCounted\nfunc value(): return 41\n")
    _write(dir.path_join("main.gd"), "extends Node\nconst H = preload('helper.gd')\nvar answer = 0\nfunc _ready(): answer = H.new().value() + 1\n")
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var good: Dictionary = runner.load_game(dir)
    await process_frame
    assert_true(good.ok, "runtime loads candidate")
    assert_eq(runner.active_game.answer, 42, "runtime-loaded script loads sibling script")
    var old = runner.active_game
    _write(dir.path_join("main.gd"), "extends Node\nfunc broken(:\n")
    var bad: Dictionary = runner.load_game(dir)
    assert_true(not bad.ok, "syntax-broken candidate is rejected")
    assert_true(runner.active_game == old, "working game survives failed candidate compile")
    runner.queue_free()
    var meta = MetadataStoreScript.new(); meta._remove_tree_abs(ProjectSettings.globalize_path(dir))

func _test_chat_pause_keeps_host_alive() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Pause Test %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates pause integration workspace")
    if not created.get("ok", false): return
    _write(created.path.path_join("main.gd"), "extends Node\nvar ticks = 0\nfunc _process(_delta): ticks += 1\n")
    var packed = load("res://main.tscn")
    var app = packed.instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame; await process_frame
    app._run_game()
    await process_frame; await process_frame
    var before = app.runner.active_game.ticks
    assert_true(before > 0, "generated game processes while chat is closed")
    app._set_chat_visible(true)
    var paused_at = app.runner.active_game.ticks
    await process_frame; await process_frame; await process_frame
    assert_eq(app.runner.active_game.ticks, paused_at, "generated game pauses while host chat remains active")
    assert_true(app.chat_overlay.visible, "host chat stays visible while tree is paused")
    app._set_chat_visible(false)
    await process_frame; await process_frame
    assert_true(app.runner.active_game.ticks > paused_at, "generated game resumes after chat closes")
    app.queue_free()
    paused = false
    store.delete_game(name)


func _test_chat_owns_mouse_mode_across_generated_reload() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Chat Input Ownership %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates chat input-ownership workspace")
    if not created.get("ok", false): return
    var source = "extends Control\nvar blocker: ColorRect\nfunc _ready():\n    blocker = ColorRect.new()\n    blocker.mouse_filter = Control.MOUSE_FILTER_STOP\n    blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n    add_child(blocker)\n    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED\n"
    _write(created.path.path_join("main.gd"), source)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var packed = load("res://main.tscn")
    var app = packed.instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    assert_true(app.chat_overlay.visible and not app.runner.has_active_game(), "existing generated game opens in chat without execution")
    app._run_game()
    assert_true(not app.chat_overlay.visible, "Run Game switches to gameplay")
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "generated UI can normally own gameplay clicks")

    app._set_chat_visible(true)
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_IGNORE, "opening chat disables generated Control mouse interception")

    var loaded: Dictionary = app.runner.load_game(created.path)
    await process_frame
    assert_true(bool(loaded.get("ok", false)), "generated game can reload while chat is open")
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_IGNORE, "newly reloaded generated Controls stay input-disabled behind chat")

    app._set_chat_visible(false)
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "closing chat restores generated UI mouse behavior")
    app.queue_free()
    paused = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    await process_frame
    store.delete_game(name)

func _test_enter_sends_chat_message() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Enter Send %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates enter-send workspace")
    if not created.get("ok", false): return
    _write(created.path.path_join("main.gd"), "extends Node2D\n")
    var packed = load("res://main.tscn")
    var app = packed.instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    app._set_chat_visible(true)
    var fake = FakeUiAgent.new(self)
    _replace_app_agent(app, fake)
    app.chat_input.text = "hello"
    app.chat_input.grab_focus()
    await process_frame
    var enter = InputEventKey.new(); enter.keycode = KEY_ENTER; enter.physical_keycode = KEY_ENTER; enter.pressed = true
    Input.parse_input_event(enter)
    for _i in 8:
        if fake.call_count > 0 and not app.agent.busy: break
        await process_frame
    assert_eq(fake.call_count, 1, "plain Enter sends the current chat message")
    assert_eq(app.chat_input.text, "", "plain Enter does not leave a newline in the composer")

    app.chat_input.text = "line one"
    app.chat_input.grab_focus()
    var shifted = InputEventKey.new(); shifted.keycode = KEY_ENTER; shifted.physical_keycode = KEY_ENTER; shifted.pressed = true; shifted.shift_pressed = true
    Input.parse_input_event(shifted)
    await process_frame
    assert_eq(fake.call_count, 1, "Shift+Enter does not send the chat message")
    assert_true("\n" in app.chat_input.text, "Shift+Enter inserts a newline for multiline editing")

    app.queue_free()
    paused = false
    await process_frame
    store.delete_game(name)

func _test_llm_snippets_reach_chat() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "LLM Snippets %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates llm-snippet workspace")
    if not created.get("ok", false): return
    _write(created.path.path_join("main.gd"), "extends Node\n")
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    app._set_chat_visible(true)
    var thinking_raw = "I should inspect the workspace files before answering this question in detail."
    var assistant_raw = "Let me check the current files first so I can answer this accurately."
    var query_raw = "find the player speed constant inside all workspace scripts"
    var tool_raw = "search_text " + JSON.stringify({"query": query_raw})
    var fake = FakeUiAgent.new(self)
    fake.send_mode = "snippets"
    _replace_app_agent(app, fake)
    app.chat_input.text = "what is the status"
    app._send_chat()
    for _i in 600:
        if not app.agent.busy: break
        await process_frame
    await process_frame
    var ui_text: String = app.transcript_view.get_parsed_text()
    var thinking_snip = "I should inspect the workspace files before answering…"
    var assistant_snip = "Let me check the current files first so I can answer…"
    var tool_snip = "search_text {\"query\":\"find the player speed consta…"
    assert_true(not app.agent.busy, "llm snippet request finishes")
    assert_true(thinking_snip in ui_text, "thinking block snippet reaches chat")
    assert_true(not thinking_raw in ui_text, "thinking block is truncated to a snippet")
    assert_true(assistant_snip in ui_text, "intermediate assistant snippet reaches chat")
    assert_true(not assistant_raw in ui_text, "intermediate assistant text is truncated to a snippet")
    assert_true(tool_snip in ui_text, "tool call snippet reaches chat")
    assert_true("All done." in ui_text, "final assistant message still posts in full")
    assert_eq(TranscriptStoreScript.new().read_all(name).size(), 2, "snippets stay out of the durable transcript")
    app.queue_free()
    paused = false
    await process_frame
    store.delete_game(name)


func _test_chat_escapes_bbcode() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    var literal = "read_file [color=red]literal[/color] [b]markup[/b]"
    app._append_chat("tool", literal)
    await process_frame
    var ui_text: String = app.transcript_view.get_parsed_text()
    assert_true(literal in ui_text, "chat renders tool/user/model text as literal text instead of parsing BBCode")
    app.queue_free()
    await process_frame


func _test_library_is_blocked_while_agent_works() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Busy Library Guard %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates busy-library guard workspace")
    if not created.get("ok", false): return
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    var fake = FakeUiAgent.new(self)
    _replace_app_agent(app, fake)
    app.chat_input.text = "tell me the current status"
    app._send_chat()
    assert_true(app.agent.busy, "agent is busy immediately after sending a request")
    var home = _find_button_with_text(app.chat_overlay, "← Library")
    assert_true(home != null, "chat exposes Library button")
    if home != null:
        assert_true(home.disabled, "Library button is disabled while agent works")
    app._return_to_library()
    assert_eq(app.current_game, name, "programmatic Return to Library is blocked while agent works")
    assert_true(not app.library_layer.visible, "library screen remains hidden while agent works")
    await process_frame; await process_frame
    assert_true(not app.agent.busy, "agent eventually finishes busy-library guard request")
    if home != null:
        assert_true(not home.disabled, "Library button is re-enabled after agent finishes")
    app.queue_free(); await process_frame
    paused = false
    store.delete_game(name)

func _test_manual_compaction_chat_feedback_and_send_guard() -> void:
    var metadata = MetadataStoreScript.new()
    var original_settings = metadata.global_settings().duplicate(true)
    var settings = original_settings.duplicate(true)
    settings.llm_call_delay_sec = 0.0
    settings.compaction_keep_recent_tokens = 800
    metadata.save_global_settings(settings)

    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Manual Compaction UI %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates manual-compaction UI workspace")
    if not created.get("ok", false):
        metadata.save_global_settings(original_settings)
        return
    _write(created.path.path_join("main.gd"), "extends Node\n")

    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame
    app._set_chat_visible(true)
    app._open_settings()

    var fake = FakeUiAgent.new(self)
    fake.compact_result = {"ok": true, "tokens_before": 9000, "tokens_after": 1200}
    fake.compact_frames = 3
    _replace_app_agent(app, fake)

    var readable = TranscriptStoreScript.new()
    var message_count_before = readable.read_all(name).size()
    app._compact_now_from_settings()
    assert_true(app.agent.busy, "manual compaction marks agent busy immediately")
    assert_true(not app.settings_dialog.visible, "manual compaction returns from Settings to chat so progress is visible")
    assert_true(not app.chat_input.editable, "chat composer is disabled while manual compaction runs")
    assert_true(app.get("send_button") != null and app.send_button.disabled, "Send button is disabled while manual compaction runs")
    assert_true(app.library_button.disabled, "Library navigation is disabled while manual compaction runs")
    var during_text: String = app.transcript_view.get_parsed_text()
    assert_true("Compacting conversation" in during_text, "manual compaction immediately posts a visible HOST progress message in chat")

    app.chat_input.text = "this must not send"
    app._send_chat()
    assert_eq(readable.read_all(name).size(), message_count_before, "new chat messages cannot enter readable transcript while manual compaction is running")

    for _i in 120:
        if not app.agent.busy: break
        await process_frame
    await process_frame
    var finished_text: String = app.transcript_view.get_parsed_text()
    assert_true(not app.agent.busy, "manual compaction finishes")
    assert_true("Compaction finished" in finished_text, "successful manual compaction posts an explicit completion message in chat")
    assert_true(app.chat_input.editable, "chat composer is re-enabled after manual compaction")
    assert_true(app.get("send_button") != null and not app.send_button.disabled, "Send button is re-enabled after manual compaction")
    assert_true(not app.library_button.disabled, "Library navigation is re-enabled after manual compaction")
    assert_eq(readable.read_all(name).size(), message_count_before, "manual compaction status messages stay ephemeral and do not pollute readable transcript")

    var failing = FakeUiAgent.new(self)
    failing.compact_result = {"ok": false, "error": "simulated Pi compaction failure"}
    _replace_app_agent(app, failing)
    app._open_settings()
    app._compact_now_from_settings()
    for _i in 120:
        if not app.agent.busy: break
        await process_frame
    await process_frame
    var failed_text: String = app.transcript_view.get_parsed_text()
    assert_true("Compaction failed" in failed_text and "simulated Pi compaction failure" in failed_text, "failed native Pi compaction posts an explicit failure message in chat")
    assert_true(app.chat_input.editable and not app.send_button.disabled, "composer is restored after failed manual compaction")

    app.queue_free()
    await process_frame
    paused = false
    store.delete_game(name)
    metadata.save_global_settings(original_settings)
func _test_app_identity_settings_and_compact_ui() -> void:
    assert_eq(str(ProjectSettings.get_setting("application/config/name", "")), "GameSmithHost", "Godot application data identity has no space")
    var metadata = MetadataStoreScript.new()
    var settings = metadata.global_settings()
    assert_eq(int(settings.get("max_agent_steps", -1)), 150, "default agent action limit is 150")
    assert_eq(float(settings.get("llm_call_delay_sec", -1.0)), 6.0, "default delay between LLM calls is 6 seconds")
    assert_eq(int(settings.get("compaction_auto_tokens", -1)), 100000, "default automatic compaction threshold is 100k tokens")
    assert_eq(int(settings.get("compaction_keep_recent_tokens", -1)), 20000, "Pi-style compaction keeps 20k recent tokens by default")
    var theme = ThemeFactoryScript.build()
    var button_box = theme.get_stylebox("normal", "Button")
    assert_true(button_box != null and button_box.content_margin_left <= 10.0 and button_box.content_margin_top <= 7.0, "buttons use compact deliberate padding")
    var original_settings = settings.duplicate(true)
    var app = load("res://main.tscn").instantiate()
    root.add_child(app); await process_frame
    var settings_button = _find_button_with_text(app.library_layer, "Settings")
    assert_true(settings_button != null, "library has a general Settings button")
    if settings_button != null:
        assert_true(settings_button.size.y <= 42.0, "library header actions stay compact instead of stretching to brand height")
    assert_true(_find_button_with_text(app.library_layer, "Logs") != null, "library exposes global logs without entering a game")
    assert_true(app.get("agent_steps_spin") != null, "settings exposes editable agent action limit")
    assert_true(app.get("llm_delay_spin") != null, "settings exposes editable LLM call delay")
    assert_true(app.get("compaction_auto_spin") != null, "settings exposes automatic compaction token threshold")
    assert_true(app.get("compaction_keep_spin") != null, "settings exposes Pi-style recent-token budget")
    assert_true(app.get("compact_now_button") != null, "settings exposes manual Compact now action")
    assert_true(not (app.settings_dialog is Window), "general Settings is an in-canvas host overlay, not a modal subwindow")
    assert_true(app.settings_dialog.get_parent() == app.host_ui_root, "Settings overlay is rendered in the reserved host UI layer")
    app._open_settings()
    assert_eq(float(app.llm_delay_spin.value), 6.0, "Settings UI loads the 6-second LLM delay default")
    app.agent_steps_spin.value = 77
    app.llm_delay_spin.value = 2.5
    if app.get("compaction_auto_spin") != null:
        app.compaction_auto_spin.value = 54000
    if app.get("compaction_keep_spin") != null:
        app.compaction_keep_spin.value = 12000
    app._save_settings()
    assert_eq(int(metadata.global_settings().get("max_agent_steps", -1)), 77, "Settings UI persists edited agent action limit")
    assert_eq(float(metadata.global_settings().get("llm_call_delay_sec", -1.0)), 2.5, "Settings UI persists edited LLM call delay")
    assert_eq(int(metadata.global_settings().get("compaction_auto_tokens", -1)), 54000, "Settings UI persists automatic compaction threshold")
    assert_eq(int(metadata.global_settings().get("compaction_keep_recent_tokens", -1)), 12000, "Settings UI persists recent-token compaction budget")
    metadata.save_global_settings(original_settings)
    var send = _find_button_with_text(app.chat_overlay, "Send")
    assert_true(send != null and send.custom_minimum_size.y <= 68.0, "chat composer Send button is not oversized")
    app.queue_free(); await process_frame

func _set_test_llm_call_delay(seconds: float) -> void:
    var metadata = MetadataStoreScript.new()
    var settings = metadata.global_settings().duplicate(true)
    settings.llm_call_delay_sec = seconds
    metadata.save_global_settings(settings)

func _find_button_with_text(node: Node, text: String) -> Button:
    if node is Button and node.text == text:
        return node
    for child in node.get_children():
        var found = _find_button_with_text(child, text)
        if found != null:
            return found
    return null

func _test_legacy_user_data_migration() -> void:
    var base = ProjectSettings.globalize_path("user://migration-fixture-%d" % Time.get_ticks_msec())
    var old_root = base.path_join("GameSmith Host")
    var new_root = base.path_join("GameSmithHost")
    DirAccess.make_dir_recursive_absolute(old_root.path_join("games/Legacy Game"))
    DirAccess.make_dir_recursive_absolute(old_root.path_join("host"))
    _write_abs(old_root.path_join("games/Legacy Game/main.gd"), "extends Node\n")
    _write_abs(old_root.path_join("host/settings.json"), '{"provider":"custom"}')
    DirAccess.make_dir_recursive_absolute(new_root.path_join("host"))
    _write_abs(new_root.path_join("host/keep.txt"), "new-data")
    var result: Dictionary = LegacyDataMigratorScript.migrate_absolute(old_root, new_root)
    assert_true(bool(result.get("ok", false)), "legacy spaced app-data root migrates into GameSmithHost")
    assert_true(FileAccess.file_exists(new_root.path_join("games/Legacy Game/main.gd")), "legacy game workspace is copied to no-space app-data root")
    assert_true(FileAccess.file_exists(new_root.path_join("host/settings.json")), "legacy host settings are copied to no-space app-data root")
    assert_eq(FileAccess.get_file_as_string(new_root.path_join("host/keep.txt")), "new-data", "migration preserves files already present in new app-data root")
    LegacyDataMigratorScript.remove_tree_absolute(base)

func _test_debug_logs_and_redaction() -> void:
    var meta = MetadataStoreScript.new(); meta.ensure()
    var global_path = AppLoggerScript.global_log_path()
    if FileAccess.file_exists(global_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(global_path))
    var game_name = "Log Test %d" % Time.get_ticks_msec()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(meta.game_meta_dir(game_name)))
    var game_path = AppLoggerScript.game_log_path(game_name)
    AppLoggerScript.global_event("test.global", "Authorization: Bearer secret-token api_key=secret-key sk-supersecret123")
    AppLoggerScript.game_event(game_name, "agent.tool", "write_file ok=true")
    assert_true(FileAccess.file_exists(global_path), "global GameSmith debug log is created")
    assert_true(FileAccess.file_exists(game_path), "per-game GameSmith debug log is created")
    var global_text = FileAccess.get_file_as_string(global_path)
    assert_true("test.global" in global_text, "global debug log records categorized events")
    assert_true(not "secret-token" in global_text and not "secret-key" in global_text and not "sk-supersecret123" in global_text, "debug logs redact authorization and API-key-like secrets")
    var game_text = FileAccess.get_file_as_string(game_path)
    assert_true("agent.tool" in game_text and "write_file" in game_text, "per-game debug log records agent tool lifecycle summaries")
    meta._remove_tree(meta.game_meta_dir(game_name))

func _write_abs(path: String, content: String) -> void:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var f = FileAccess.open(path, FileAccess.WRITE); f.store_string(content); f.close()

func _test_provider_settings_surface() -> void:
    var names = PiProviderCatalogScript.display_names()
    assert_true(names.has("custom"), "Pi provider list exposes a custom OpenAI-compatible provider")
    assert_true(names.has("openai_subscription"), "Pi provider list exposes global OpenAI subscription auth")
    var defaults = PiProviderCatalogScript.defaults()
    assert_eq(str(defaults.get("openrouter", "")), "openai/gpt-5.6", "Pi provider catalog retains the OpenRouter default model")
    assert_eq(PiProviderCatalogScript.custom_base_url("http://127.0.0.1:1234/v1/chat/completions"), "http://127.0.0.1:1234/v1", "custom Pi base URL strips a chat-completions suffix")
    assert_true(PiProviderCatalogScript.uses_global_auth("openai_subscription"), "OpenAI subscription delegates auth to Pi")
    var settings = MetadataStoreScript.new().global_settings()
    assert_true(settings.has("custom_base_url"), "global settings include custom /v1 base address")
    assert_true(settings.has("reasoning_effort"), "global settings include Pi reasoning effort")
    assert_true(settings.has("llm_call_delay_sec"), "global settings include configurable delay between Pi provider calls")
func _test_pi_request_has_no_host_deadline_or_fake_completion() -> void:
    var source = FileAccess.get_file_as_string("res://src/agent/pi_agent_controller.gd")
    assert_true(not "20 * 60 * 1000" in source and not "20 minute host deadline" in source, "Pi requests have no arbitrary host wall-clock deadline")
    assert_true(not 'final_text = "Done."' in source, "GameSmith never invents a fake assistant completion message")
    var rpc_source = FileAccess.get_file_as_string("res://src/pi/pi_rpc_session.gd")
    assert_true(not "timeout_sec" in rpc_source and not "Timed out waiting for Pi RPC response" in rpc_source, "Pi RPC commands wait for a response or process exit instead of an artificial timeout")
    var extension_source = FileAccess.get_file_as_string("res://tools/pi/gamesmith-extension.ts")
    assert_true(not "Timed out waiting for GameSmith host tool" in extension_source and not "Date.now() + 60_000" in extension_source, "GameSmith Pi host tools wait for completion or abort instead of an artificial timeout")

func _test_stale_pi_settlement_does_not_finish_next_request() -> void:
    var agent = PiAgentControllerScript.new()
    root.add_child(agent)
    agent.busy = true
    agent.turn_count = 0
    agent._on_pi_record({"type": "agent_settled"})
    assert_true(not agent.has_meta("_pi_settled"), "settlement from a previous aborted run cannot settle a new request before its first Pi turn")
    agent._on_pi_record({"type": "turn_start"})
    agent._on_pi_record({"type": "agent_settled"})
    assert_true(agent.has_meta("_pi_settled"), "settlement is accepted after the current request has actually started a Pi turn")
    agent.queue_free()
    await process_frame

func _write(path: String, content: String) -> void:
    var f = FileAccess.open(path, FileAccess.WRITE); f.store_string(content); f.close()
