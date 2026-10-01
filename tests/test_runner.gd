extends SceneTree

const PathUtilsScript = preload("res://src/core/path_utils.gd")
const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const AgentControllerScript = preload("res://src/agent/agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const ConversationStoreScript = preload("res://src/core/conversation_store.gd")
const ProviderFactoryScript = preload("res://src/providers/provider_factory.gd")
const ThemeFactoryScript = preload("res://src/ui/theme_factory.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const LegacyDataMigratorScript = preload("res://src/core/legacy_data_migrator.gd")

var failures = 0
var passed = 0

class FakeProvider:
    extends RefCounted
    var tree: SceneTree
    var responses: Array = []
    var seen_messages: Array = []
    var call_count = 0

    func _init(p_tree: SceneTree):
        tree = p_tree

    func push(response: Dictionary) -> void:
        responses.append(response)

    func complete(messages: Array, _tools: Array) -> Dictionary:
        call_count += 1
        seen_messages.append(messages.duplicate(true))
        await tree.process_frame
        if responses.is_empty():
            return {"ok": false, "error": "Fake provider exhausted."}
        return responses.pop_front()

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
    await _test_legacy_user_data_migration()
    await _test_debug_logs_and_redaction()
    await _test_agent_generation_and_second_edit()
    await _test_agent_rejects_false_done_on_empty_workspace()
    await _test_agent_requires_reload_after_code_change()
    await _test_agent_recovers_from_failed_reload_before_completion()
    await _test_agent_history_survives_restart_and_keeps_stable_prefix()
    await _test_legacy_transcript_is_imported_into_agent_history()
    await _test_provider_settings_surface()
    await _test_custom_provider_and_reasoning_payload()
    await _test_agent_llm_call_delay()
    await _test_agent_malformed_tool_arguments()
    await _test_agent_provider_failure()
    await _test_agent_step_limit()
    print("TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

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
    _write(dir.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var H = load(get_script().resource_path.get_base_dir() + '/helper.gd')\n    answer = H.new().value() + 1\n")
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
    assert_true(not app.chat_overlay.visible, "existing generated game starts with chat closed")
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
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Hi."}})
    app.agent.provider_override = fake
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
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": assistant_raw, "reasoning_content": null, "reasoning": thinking_raw, "tool_calls": [_tool_call("search-1", "search_text", {"query": query_raw})]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "All done."}})
    app.agent.provider_override = fake
    app.chat_input.text = "what is the status"
    app._send_chat()
    for _i in 600:
        if not app.agent.busy: break
        await process_frame
    await process_frame
    var ui_text: String = app.transcript_view.get_parsed_text()
    var thinking_snip = thinking_raw.left(50) + "…"
    var assistant_snip = assistant_raw.left(50) + "…"
    var tool_snip = tool_raw.left(50) + "…"
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
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Still here."}})
    app.agent.provider_override = fake
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

func _test_app_identity_settings_and_compact_ui() -> void:
    assert_eq(str(ProjectSettings.get_setting("application/config/name", "")), "GameSmithHost", "Godot application data identity has no space")
    var metadata = MetadataStoreScript.new()
    var settings = metadata.global_settings()
    assert_eq(int(settings.get("max_agent_steps", -1)), 150, "default agent action limit is 150")
    assert_eq(float(settings.get("llm_call_delay_sec", -1.0)), 6.0, "default delay between LLM calls is 6 seconds")
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
    app._open_settings()
    assert_eq(float(app.llm_delay_spin.value), 6.0, "Settings UI loads the 6-second LLM delay default")
    app.agent_steps_spin.value = 77
    app.llm_delay_spin.value = 2.5
    app._save_settings()
    assert_eq(int(metadata.global_settings().get("max_agent_steps", -1)), 77, "Settings UI persists edited agent action limit")
    assert_eq(float(metadata.global_settings().get("llm_call_delay_sec", -1.0)), 2.5, "Settings UI persists edited LLM call delay")
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

func _test_agent_generation_and_second_edit() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Agent E2E %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates agent end-to-end workspace")
    if not created.get("ok", false): return

    var runner = GameRunnerScript.new(); root.add_child(runner)
    var tools = GameToolsScript.new(created.path, runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("write-1", "write_file", {"path": "main.gd", "content": "extends Node2D\nvar speed = 100.0\nfunc _process(delta):\n    position.x += speed * delta\n"}),
        _tool_call("commit-1", "git_commit", {"message": "Create moving game"}),
        _tool_call("reload-1", "reload_game", {})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Built a moving game."}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("patch-1", "patch_file", {"path": "main.gd", "old_text": "var speed = 100.0", "new_text": "var speed = 240.0"}),
        _tool_call("commit-2", "git_commit", {"message": "Increase player speed"}),
        _tool_call("reload-2", "reload_game", {})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Player speed increased."}})

    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, tools)
    agent.provider_override = fake

    agent.send_player_request("Make a tiny moving game")
    var first_ok = await agent.finished
    assert_true(first_ok, "simulated LLM generation request finishes successfully")
    assert_true(runner.has_active_game(), "simulated LLM reload produces a running game")
    assert_true(runner.active_game is Node2D, "generated game is an instantiated playable Node2D")
    assert_eq(runner.active_game.speed, 100.0, "first generated game uses requested initial speed")
    var x_before = runner.active_game.position.x
    await process_frame; await process_frame
    assert_true(runner.active_game.position.x > x_before, "generated game actually processes after reload")

    var transcript_store = TranscriptStoreScript.new()
    var first_transcript = transcript_store.read_all(name)
    assert_eq(first_transcript.size(), 2, "first request persists user and assistant transcript entries")
    assert_eq(str(first_transcript[0].content), "Make a tiny moving game", "transcript persists first player request")
    assert_eq(str(first_transcript[1].content), "Built a moving game.", "transcript persists first assistant response")

    agent.send_player_request("Make the player faster")
    var second_ok = await agent.finished
    assert_true(second_ok, "simulated second LLM request finishes successfully")
    assert_eq(runner.active_game.speed, 240.0, "second request patches and reloads the running game")
    var final_source = FileAccess.get_file_as_string(created.path.path_join("main.gd"))
    assert_true("var speed = 240.0" in final_source, "second request persists the modified source")
    var git_log: Dictionary = store.git.log(created.path, 5)
    assert_true("Increase player speed" in str(git_log.get("output", "")) and "Create moving game" in str(git_log.get("output", "")), "simulated LLM creates coherent Git milestones")
    var final_transcript = transcript_store.read_all(name)
    assert_eq(final_transcript.size(), 4, "second request appends to persistent transcript")
    assert_eq(str(final_transcript[3].content), "Player speed increased.", "transcript persists second assistant response")
    var debug_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(name))
    assert_true("agent.request" in debug_log and "agent.tool" in debug_log and "agent.finished" in debug_log, "simulated agent lifecycle is available in the per-game debug log")

    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_rejects_false_done_on_empty_workspace() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "False Done %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates false-done workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Done."}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("write-main", "write_file", {"path": "main.gd", "content": "extends Node2D\nvar ticks = 0\nfunc _process(_delta): ticks += 1\n"}),
        _tool_call("reload-main", "reload_game", {})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Built and loaded the game."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("create a simple tetris 3d game")
    var ok = await agent.finished
    assert_true(ok, "false Done response is recovered within the same player request")
    assert_eq(fake.call_count, 3, "empty-workspace completion claim cannot terminate before tool work")
    assert_true(FileAccess.file_exists(created.path.path_join("main.gd")), "recovered request actually writes main.gd")
    assert_true(runner.has_active_game(), "recovered request actually reloads a generated game")
    var visible = TranscriptStoreScript.new().read_all(name)
    assert_eq(str(visible[-1].content), "Built and loaded the game.", "premature Done is hidden from readable transcript")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_requires_reload_after_code_change() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Reload Guard %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates reload-guard workspace")
    if not created.get("ok", false): return
    _write(created.path.path_join("main.gd"), "extends Node2D\nvar speed = 10.0\n")
    var runner = GameRunnerScript.new(); root.add_child(runner)
    assert_true(runner.load_game(created.path).ok, "reload-guard baseline game loads")
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("patch-speed", "patch_file", {"path": "main.gd", "old_text": "var speed = 10.0", "new_text": "var speed = 20.0"})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Done."}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [_tool_call("reload-speed", "reload_game", {})]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Speed changed and loaded."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("make it faster")
    var ok = await agent.finished
    assert_true(ok, "code mutation cannot finish until its new code is reloaded")
    assert_eq(fake.call_count, 4, "premature post-edit Done triggers another agent step")
    assert_eq(runner.active_game.speed, 20.0, "required reload activates edited code")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_recovers_from_failed_reload_before_completion() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Failed Reload Guard %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates failed-reload workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("write-broken", "write_file", {"path": "main.gd", "content": "extends Node2D\nfunc broken(:\n"}),
        _tool_call("reload-broken", "reload_game", {})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Done."}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [
        _tool_call("fix-broken", "write_file", {"path": "main.gd", "content": "extends Node2D\nvar repaired = true\n"}),
        _tool_call("reload-fixed", "reload_game", {})
    ]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Fixed and loaded."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("build a game")
    var ok = await agent.finished
    assert_true(ok, "failed reload cannot be followed by a false successful completion")
    assert_eq(fake.call_count, 4, "failed reload plus Done is forced back into repair loop")
    assert_true(runner.has_active_game() and runner.active_game.repaired, "repair loop ends with a working generated game")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_history_survives_restart_and_keeps_stable_prefix() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Agent History %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates persistent-history workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var tools = GameToolsScript.new(created.path, runner)

    var first = FakeProvider.new(self)
    first.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [_tool_call("history-status", "git_status", {})]}})
    first.push({"ok": true, "message": {"role": "assistant", "content": "Blue remembered."}})
    var agent1 = AgentControllerScript.new(); root.add_child(agent1)
    agent1.configure(name, tools); agent1.provider_override = first
    agent1.send_player_request("Remember blue")
    assert_true(await agent1.finished, "first persistent-history request succeeds")
    agent1.queue_free(); await process_frame

    var second = FakeProvider.new(self)
    second.push({"ok": true, "message": {"role": "assistant", "content": "You said blue."}})
    var agent2 = AgentControllerScript.new(); root.add_child(agent2)
    agent2.configure(name, tools); agent2.provider_override = second
    agent2.send_player_request("What did I say?")
    assert_true(await agent2.finished, "request after agent restart succeeds")
    var raw_history = ConversationStoreScript.new().read_all(name)
    assert_true(raw_history.size() >= 4, "full raw agent trace remains durable on disk")
    if raw_history.size() >= 4:
        assert_true(not (raw_history[1].get("tool_calls", []) as Array).is_empty(), "raw history retains assistant tool calls for debugging")
        assert_eq(str(raw_history[2].get("role", "")), "tool", "raw history retains tool results for debugging")
    var resumed: Array = second.seen_messages[0]
    assert_eq(resumed.size(), 4, "restarted agent replays compact completed conversation plus new user message")
    if resumed.size() >= 4:
        assert_eq(str(resumed[1].get("content", "")), "Remember blue", "compacted history includes previous user message")
        assert_eq(str(resumed[2].get("content", "")), "Blue remembered.", "compacted history includes previous final assistant response")
        assert_true(not resumed[2].has("tool_calls"), "old completed tool trace is omitted from provider replay")
        assert_eq(str(resumed[3].get("content", "")), "What did I say?", "new user message follows compact stable history")
    var stable_prefix_json = JSON.stringify(resumed.slice(0, maxi(0, resumed.size() - 1)))
    agent2.queue_free(); await process_frame

    var third = FakeProvider.new(self)
    third.push({"ok": true, "message": {"role": "assistant", "content": "Still blue."}})
    var agent3 = AgentControllerScript.new(); root.add_child(agent3)
    agent3.configure(name, tools); agent3.provider_override = third
    agent3.send_player_request("And now?")
    assert_true(await agent3.finished, "second request after restart succeeds")
    var third_messages: Array = third.seen_messages[0]
    if resumed.size() >= 1 and third_messages.size() >= resumed.size() + 1:
        assert_eq(JSON.stringify(third_messages.slice(0, resumed.size() - 1)), stable_prefix_json, "unchanged conversation prefix is byte-stable for provider prompt caching")
    else:
        assert_true(false, "third request retains the previous stable conversation prefix")

    agent3.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)


func _test_legacy_transcript_is_imported_into_agent_history() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Legacy History %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates legacy-history workspace")
    if not created.get("ok", false): return
    var legacy = TranscriptStoreScript.new()
    legacy.append(name, "user", "Build a blue square")
    legacy.append(name, "assistant", "Built the blue square.")
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "You built a blue square."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("What did we build?")
    assert_true(await agent.finished, "legacy transcript migration request succeeds")
    var messages: Array = fake.seen_messages[0]
    assert_eq(messages.size(), 4, "legacy readable transcript becomes provider-visible history on first upgraded request")
    if messages.size() >= 4:
        assert_eq(str(messages[1].get("content", "")), "Build a blue square", "legacy user message is imported")
        assert_eq(str(messages[2].get("content", "")), "Built the blue square.", "legacy assistant message is imported")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_provider_settings_surface() -> void:
    var names = ProviderFactoryScript.display_names()
    assert_true(names.has("custom"), "provider list exposes a custom OpenAI-compatible provider")
    var settings = MetadataStoreScript.new().global_settings()
    assert_true(settings.has("custom_base_url"), "global settings include custom /v1 base address")
    assert_true(settings.has("reasoning_effort"), "global settings include reasoning_effort")
    assert_true(settings.has("llm_call_delay_sec"), "global settings include configurable delay between LLM calls")


func _test_custom_provider_and_reasoning_payload() -> void:
    var owner = Node.new(); root.add_child(owner)
    var provider = ProviderFactoryScript.make(owner, "custom", "local-model", {"custom": ""}, "session", {"custom_base_url": "http://127.0.0.1:1234/v1/", "reasoning_effort": "high"})
    assert_true(provider != null, "custom provider can be created without an API key")
    if provider != null:
        assert_eq(provider.endpoint, "http://127.0.0.1:1234/v1/chat/completions", "custom /v1 base address normalizes to chat completions endpoint")
        var payload: Dictionary = provider.build_payload([{"role": "user", "content": "hello"}], [])
        assert_eq(str(payload.get("reasoning_effort", "")), "high", "provider sends reasoning_effort exactly in OpenAI-compatible request payload")
        assert_true(not payload.has("temperature"), "reasoning payload omits incompatible temperature when effort is enabled")
    var no_reasoning = ProviderFactoryScript.make(owner, "custom", "local-model", {}, "session", {"custom_base_url": "http://127.0.0.1:1234", "reasoning_effort": ""})
    assert_eq(no_reasoning.endpoint, "http://127.0.0.1:1234/v1/chat/completions", "custom address without /v1 receives the v1 suffix")
    var default_payload: Dictionary = no_reasoning.build_payload([], [])
    assert_true(not default_payload.has("reasoning_effort"), "provider-default reasoning omits reasoning_effort from request")
    owner.queue_free(); await process_frame

func _test_agent_llm_call_delay() -> void:
    var metadata = MetadataStoreScript.new()
    var original_settings = metadata.global_settings().duplicate(true)
    var settings = original_settings.duplicate(true)
    settings.provider = "custom"
    settings.model = "delay-test-%d" % Time.get_ticks_msec()
    settings.llm_call_delay_sec = 0.06
    metadata.save_global_settings(settings)

    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "LLM Delay %d" % Time.get_ticks_msec()
    var created = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates provider-delay workspace")
    if not created.get("ok", false):
        metadata.save_global_settings(original_settings)
        return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [_tool_call("delay-status", "git_status", {})]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Status checked."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    var started = Time.get_ticks_msec()
    agent.send_player_request("check status")
    assert_true(await agent.finished, "agent succeeds with configured provider pacing")
    var elapsed = Time.get_ticks_msec() - started
    assert_true(elapsed >= 45, "configured LLM delay inserts a real quiet period between provider calls")
    var debug_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(name))
    assert_true("provider.delay" in debug_log, "provider pacing is visible in per-game debug logs")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)
    metadata.save_global_settings(original_settings)

func _test_agent_malformed_tool_arguments() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Malformed Tool %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates malformed-tool workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [{"id": "bad-args", "type": "function", "function": {"name": "git_commit", "arguments": "{ definitely not json"}}]}})
    fake.push({"ok": true, "message": {"role": "assistant", "content": "Recovered from malformed arguments."}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("Try a malformed tool call")
    var ok = await agent.finished
    assert_true(ok, "malformed tool arguments are recoverable by the model")
    assert_eq(fake.call_count, 2, "malformed call result is returned to provider for another step")
    var second_messages: Array = fake.seen_messages[1]
    var tool_message: Dictionary = second_messages[second_messages.size() - 1]
    assert_true("Malformed tool arguments" in str(tool_message.get("content", "")), "malformed JSON becomes an explicit tool error instead of executing defaults")
    var log: Dictionary = store.git.log(created.path, 5)
    assert_true(not "Update generated game" in str(log.get("output", "")), "malformed git_commit does not create an unintended default commit")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_provider_failure() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Provider Failure %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates provider-failure workspace")
    if not created.get("ok", false): return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    fake.push({"ok": false, "error": "simulated provider outage"})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("Build something")
    var ok = await agent.finished
    assert_true(not ok, "provider failure marks request unsuccessful")
    assert_true(not agent.busy, "provider failure clears busy state")
    var entries = TranscriptStoreScript.new().read_all(name)
    assert_eq(entries.size(), 2, "provider failure is persisted alongside player request")
    assert_true("simulated provider outage" in str(entries[-1].content), "provider failure transcript contains provider error")
    assert_true(not runner.has_active_game(), "provider failure does not mutate or launch the game")
    var debug_log = FileAccess.get_file_as_string(AppLoggerScript.game_log_path(name))
    assert_true("provider.error" in debug_log and "agent.failed" in debug_log, "per-game log captures provider and agent failure events")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)

func _test_agent_step_limit() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var meta = MetadataStoreScript.new()
    var original_settings = meta.global_settings().duplicate(true)
    var settings = original_settings.duplicate(true)
    settings.max_agent_steps = 3
    meta.save_global_settings(settings)
    var name = "Step Limit %d" % Time.get_ticks_msec()
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates step-limit workspace")
    if not created.get("ok", false):
        meta.save_global_settings(original_settings)
        return
    var runner = GameRunnerScript.new(); root.add_child(runner)
    var fake = FakeProvider.new(self)
    for i in 5:
        fake.push({"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": [_tool_call("status-%d" % i, "git_status", {})]}})
    var agent = AgentControllerScript.new(); root.add_child(agent)
    agent.configure(name, GameToolsScript.new(created.path, runner)); agent.provider_override = fake
    agent.send_player_request("Keep checking forever")
    var ok = await agent.finished
    assert_true(not ok, "configured step limit terminates runaway agent request")
    assert_eq(fake.call_count, 3, "agent obeys persisted max_agent_steps setting")
    assert_true(not agent.busy, "step-limit termination clears busy state")
    var entries = TranscriptStoreScript.new().read_all(name)
    assert_true("step limit" in str(entries[-1].content).to_lower(), "step-limit failure is persisted in transcript")
    agent.queue_free(); runner.queue_free(); await process_frame
    store.delete_game(name)
    meta.save_global_settings(original_settings)

func _tool_call(id: String, name: String, args: Dictionary) -> Dictionary:
    return {"id": id, "type": "function", "function": {"name": name, "arguments": JSON.stringify(args)}}

func _write(path: String, content: String) -> void:
    var f = FileAccess.open(path, FileAccess.WRITE); f.store_string(content); f.close()
