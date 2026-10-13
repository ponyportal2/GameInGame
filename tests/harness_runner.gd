extends SceneTree

class RetiringSession extends RefCounted:
    var retired := false
    func retire() -> void:
        retired = true

var failures := 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error(message)
    else:
        print("PASS: " + message)

func run() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    check(app.get("harness_option") != null, "new game offers a harness choice")
    if app.get("harness_option") == null:
        app.queue_free()
        quit(1)
        return
    app.name_edit.text = "Command harness fixture"
    app.harness_option.select(1)
    app._create_game()
    await process_frame
    check(app.metadata.read_game(app.current_game).get("harness") == "command-code", "selected harness persists in game metadata")
    check(app.agent.get_script().resource_path.ends_with("command_code_agent_controller.gd"), "command-code game uses its own controller")
    app._open_settings()
    check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable, "command-code disables provider, model, and credentials")
    check(app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and not app.compact_now_button.disabled, "command-code exposes host threshold and native manual compaction")
    check(app.agent_steps_spin.editable == false and app.llm_delay_spin.editable == false and app.reasoning_option.disabled, "command-code owns reasoning and turn policy")
    check(not app.rendered_tests_check.disabled, "host testing permissions remain available")
    app.metadata.save_global_settings(app.metadata.global_settings())
    var before = app.metadata.global_settings()
    app.model_edit.text = "must not save"
    app.compaction_auto_spin.value = 42000
    app._save_settings()
    var after = app.metadata.global_settings()
    check(after.compaction_auto_tokens == 42000, "command-code threshold persists")
    before.compaction_auto_tokens = 42000
    for key in before:
        check(after.get(key) == before[key], "command-code preserves setting " + key)
    app._show_library()
    check(app.harness_option.item_count == 7, "new games offer Pi, Command-code, OpenCode, Codex, Cline, Cursor and Grok Build")
    if app.harness_option.item_count >= 3:
        app.name_edit.text = "OpenCode fixture"
        app.harness_option.select(2)
        app._create_game()
        check(app.metadata.read_game(app.current_game).get("harness") == "opencode", "OpenCode selection persists")
        check(app.agent.get_script().resource_path.ends_with("opencode_agent_controller.gd"), "OpenCode game uses its own controller")
        app._open_settings()
        check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable, "OpenCode disables model and provider overrides")
        check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "OpenCode disables all host compaction controls")
        check(app.reasoning_option.disabled and not app.agent_steps_spin.editable and not app.llm_delay_spin.editable, "OpenCode owns agent policy")
        var opencode_before = app.metadata.global_settings()
        app.model_edit.text = "must not save"
        app.compaction_auto_spin.value = 999
        app.compaction_keep_spin.value = 999
        app.auto_reload_check.button_pressed = true
        app._save_settings()
        var opencode_after = app.metadata.global_settings()
        for key in opencode_before:
            if key != "auto_approve_reloads":
                check(opencode_after.get(key) == opencode_before[key], "OpenCode preserves setting " + key)
        check(opencode_after.auto_approve_reloads, "OpenCode host reload setting remains editable")
        app.metadata.save_global_settings(opencode_before)
        app._show_library()
    if app.harness_option.item_count >= 4:
        app.name_edit.text = "Codex fixture"
        app.harness_option.select(3)
        app._create_game()
        check(app.metadata.read_game(app.current_game).get("harness") == "codex", "Codex selection persists")
        check(app.agent.get_script().resource_path.ends_with("codex_agent_controller.gd"), "Codex uses its own controller")
        app._open_settings()
        check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable and app.reasoning_option.disabled, "Codex owns provider, model, credentials and reasoning")
        check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "Codex owns all compaction settings")
        var codex_before = app.metadata.global_settings()
        app.model_edit.text = "must not save"
        app.compaction_auto_spin.value = 999
        app.compaction_keep_spin.value = 999
        app.auto_reload_check.button_pressed = true
        app._save_settings()
        var codex_after = app.metadata.global_settings()
        for key in codex_before:
            if key != "auto_approve_reloads":
                check(codex_after.get(key) == codex_before[key], "Codex preserves setting " + key)
        check(codex_after.auto_approve_reloads, "Codex host reload setting remains editable")
        app.metadata.save_global_settings(codex_before)
        app._show_library()
    if app.harness_option.item_count >= 5:
        app.name_edit.text = "Cline fixture"
        app.harness_option.select(4)
        app._create_game()
        check(app.metadata.read_game(app.current_game).get("harness") == "cline", "Cline selection persists")
        check(app.agent.get_script().resource_path.ends_with("cline_agent_controller.gd"), "Cline uses its own controller")
        app._open_settings()
        check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable and app.reasoning_option.disabled, "Cline owns provider, model, credentials and reasoning")
        check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "Cline owns all compaction settings")
        var cline_before = app.metadata.global_settings()
        app.model_edit.text = "must not save"
        app.compaction_auto_spin.value = 999
        app.compaction_keep_spin.value = 999
        app.auto_reload_check.button_pressed = true
        app._save_settings()
        var cline_after = app.metadata.global_settings()
        for key in cline_before:
            if key != "auto_approve_reloads":
                check(cline_after.get(key) == cline_before[key], "Cline preserves setting " + key)
        check(cline_after.auto_approve_reloads, "Cline host reload setting remains editable")
        app.metadata.save_global_settings(cline_before)
        app._show_library()
    if app.harness_option.item_count >= 6:
        app.name_edit.text = "Cursor fixture"
        app.harness_option.select(5)
        app._create_game()
        check(app.metadata.read_game(app.current_game).get("harness") == "cursor", "Cursor selection persists")
        check(app.agent.get_script().resource_path.ends_with("cursor_agent_controller.gd"), "Cursor uses its own controller")
        app._open_settings()
        check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable and app.reasoning_option.disabled, "Cursor owns provider, model, credentials and reasoning")
        check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "Cursor owns all compaction settings")
        var cursor_before = app.metadata.global_settings()
        app.model_edit.text = "must not save"
        app.compaction_auto_spin.value = 999
        app.compaction_keep_spin.value = 999
        app.auto_reload_check.button_pressed = true
        app._save_settings()
        var cursor_after = app.metadata.global_settings()
        for key in cursor_before:
            if key != "auto_approve_reloads":
                check(cursor_after.get(key) == cursor_before[key], "Cursor preserves setting " + key)
        check(cursor_after.auto_approve_reloads, "Cursor host reload setting remains editable")
        app.metadata.save_global_settings(cursor_before)
        app._show_library()
    if app.harness_option.item_count >= 7:
        app.name_edit.text = "Grok Build fixture"
        app.harness_option.select(6)
        app._create_game()
        check(app.metadata.read_game(app.current_game).get("harness") == "grok-build", "Grok Build selection persists")
        check(app.agent.get_script().resource_path.ends_with("grok_build_agent_controller.gd"), "Grok Build uses its own controller")
        app._open_settings()
        check(app.provider_option.disabled and not app.model_edit.editable and not app.key_edit.editable and app.reasoning_option.disabled, "Grok Build owns provider, model, credentials and reasoning")
        check(not app.compaction_auto_spin.editable and not app.compaction_keep_spin.editable and app.compact_now_button.disabled, "Grok Build owns all compaction settings")
        var grok_before = app.metadata.global_settings()
        app.model_edit.text = "must not save"
        app.compaction_auto_spin.value = 999
        app.compaction_keep_spin.value = 999
        app.auto_reload_check.button_pressed = true
        app._save_settings()
        var grok_after = app.metadata.global_settings()
        for key in grok_before:
            if key != "auto_approve_reloads":
                check(grok_after.get(key) == grok_before[key], "Grok Build preserves setting " + key)
        check(grok_after.auto_approve_reloads, "Grok Build host reload setting remains editable")
        app.metadata.save_global_settings(grok_before)
        app._show_library()
    app.name_edit.text = "Pi fixture"
    app.harness_option.select(0)
    app._create_game()
    app._open_settings()
    check(not app.provider_option.disabled and app.model_edit.editable and app.compaction_auto_spin.editable, "Pi controls restore for a Pi game")
    check(app.metadata.read_game(app.current_game).get("harness") == "pi", "Pi selection persists")
    check(app.get("game_harness_option") != null, "existing games offer harness switching")
    if app.get("game_harness_option") != null:
        var name = app.current_game
        var original_runner = app.runner
        var original_tools = app.tools
        app.transcript.append(name, "user", "Preserve this history")
        var workspace_file = app.store.game_path(name).path_join("keep.txt")
        var file = FileAccess.open(workspace_file, FileAccess.WRITE)
        file.store_string("keep")
        file.close()
        var session_markers: Array[String] = []
        for harness in ["pi", "command-code", "opencode", "codex", "cline", "cursor", "grok-build"]:
            var session_dir = app.metadata.game_meta_dir(name).path_join(harness)
            DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(session_dir))
            var session_path = session_dir.path_join("switch-preservation.txt")
            var session_file = FileAccess.open(session_path, FileAccess.WRITE)
            session_file.store_string("preserved native session")
            session_file.close()
            session_markers.append(session_path)
        for pair in [[1, "command-code"], [2, "opencode"], [3, "codex"], [4, "cline"], [5, "cursor"], [6, "grok-build"], [0, "pi"]]:
            app._open_settings()
            app.game_harness_option.select(pair[0])
            app._close_settings()
            check(app.metadata.read_game(name).harness != pair[1], "cancel leaves harness unchanged")
            app._open_settings()
            var previous_agent = app.agent
            var previous_session = RetiringSession.new()
            previous_agent.rpc = previous_session
            app.game_harness_option.select(pair[0])
            app._save_settings()
            check(app.metadata.read_game(name).harness == pair[1], "saved switch persists " + pair[1])
            check(app.agent != previous_agent, "saved switch replaces controller")
            check(previous_session.retired, "switch retires the previous backend")
            check(not previous_agent.is_inside_tree(), "previous controller shuts down synchronously")
            for session_path in session_markers:
                check(FileAccess.get_file_as_string(session_path) == "preserved native session", "switch retains harness session data")
            check(app.runner == original_runner and app.tools == original_tools, "switch preserves live runner and tools")
            check(FileAccess.get_file_as_string(workspace_file) == "keep", "switch preserves workspace")
            check(app.transcript.read_all(name).any(func(entry): return entry.content == "Preserve this history"), "switch preserves transcript")
            app._open_settings()
            check(app.provider_option.disabled == (pair[0] != 0), "settings follow saved harness")
            await process_frame
        app.agent.busy = true
        app._open_settings()
        check(app.game_harness_option.disabled, "busy agent disables harness selector")
        var busy_agent = app.agent
        app.game_harness_option.select(2)
        app._save_settings()
        check(app.agent == busy_agent and app.metadata.read_game(name).harness == "pi", "save rejects switching while busy")
        app.agent.busy = false
        app._show_library()
        app._open_settings()
        check(app.game_harness_option.disabled, "library settings disable per-game harness")
        app._close_settings()
        app._open_game(name)
        check(app.agent.get_script().resource_path.ends_with("pi_agent_controller.gd"), "reopening uses saved harness")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
