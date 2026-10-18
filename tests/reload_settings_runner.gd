extends SceneTree

class FailingMetadata extends "res://src/core/metadata_store.gd":
    var failure := ""
    var failures_seen := 0
    var archived_at_failure := false

    func save_global_settings(data: Dictionary) -> bool:
        if failure == "global":
            failures_seen += 1
            return false
        return super.save_global_settings(data)

    func save_credentials(data: Dictionary) -> bool:
        if failure == "credentials":
            failures_seen += 1
            return false
        return super.save_credentials(data)

    func write_game(game: String, data: Dictionary) -> bool:
        if failure == "provider" or (failure == "commit" and not data.get("blender_enabled", true)):
            failures_seen += 1
            archived_at_failure = not FileAccess.file_exists(game_meta_dir(game).path_join("codex/session.json"))
            return false
        return super.write_game(game, data)

var failures := 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value:
        failures += 1

func run() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    check(app.get("auto_reload_check") != null, "settings offers automatic reload approval")
    if app.get("auto_reload_check") == null:
        app.queue_free()
        quit(1)
        return
    check(not app.metadata.global_settings().get("auto_approve_reloads", false), "automatic approval defaults off")
    check(app.metadata.global_settings().get("image_backend", "") == "", "Image generation has no default vendor")
    app._open_settings()
    check(not is_instance_valid(app.image_probe), "Opening ordinary settings does not start native image processes")
    app._select_image_backend("codex")
    app._save_settings()
    check(app.metadata.global_settings().get("image_backend", "") == "codex", "Selected native image backend persists")
    app._open_settings()
    check(app.image_backend_option.get_item_metadata(app.image_backend_option.selected) == "codex", "Settings restores selected image backend")
    app._select_image_backend("")
    app._save_settings()
    check(not app.metadata.global_settings().get("auto_approve_blender_scripts", true), "Blender automatic approval defaults off")
    check(app.get("auto_blender_check") != null, "settings offers independent Blender automatic approval")
    if app.get("auto_blender_check") == null:
        app.queue_free()
        quit(1)
        return
    for harness in [0, 1]:
        app.name_edit.text = "Reload settings %d" % harness
        app.harness_option.select(harness)
        app._create_game()
        app._open_settings()
        check(not app.metadata.read_game(app.current_game).blender_enabled and not app.tools.blender_enabled, "new games omit Blender by default for harness %d" % harness)
        check(not app.game_blender_check.button_pressed, "settings restores disabled Blender tools")
        check(not app.tools.blender({"action": "guide"}).ok and not is_instance_valid(app.tools.blender_supervisor), "disabled Blender guide does not create a supervisor")
        var prompt_config = preload("res://src/pi/pi_runtime_config.gd")
        check(not "Blender" in prompt_config._game_prompt(false) and not "blender" in prompt_config._game_prompt(false), "disabled instructions omit Blender")
        check("blender(action=" in prompt_config._game_prompt(true), "enabled instructions retain Blender workflow")
        app.agent.bridge_dir = "retired-availability-fixture"
        app.game_blender_check.button_pressed = true
        app._save_settings()
        check(app.metadata.read_game(app.current_game).blender_enabled and app.tools.blender_enabled, "Blender can be added later for harness %d" % harness)
        check(app.agent.bridge_dir == "", "availability change retires the previous harness runtime")
        app._open_settings()
        check(app.game_blender_check.button_pressed, "enabled Blender persists in settings")
        app.agent.busy = true
        app.game_blender_check.button_pressed = false
        app._save_settings()
        check(app.metadata.read_game(app.current_game).blender_enabled, "availability cannot change during an active turn")
        app.agent.busy = false
        app._save_settings()
        check(not app.metadata.read_game(app.current_game).blender_enabled and not app.tools.blender_enabled, "Blender can be removed later for harness %d" % harness)
        app._open_settings()
        check(not app.auto_reload_check.disabled, "host approval setting is available for harness %d" % harness)
        app.auto_reload_check.button_pressed = true
        app.auto_blender_check.button_pressed = true
        app._save_settings()
        check(app.metadata.global_settings().get("auto_approve_blender_scripts", false), "Blender approval persists for harness %d" % harness)
        app._open_settings()
        check(app.auto_blender_check.button_pressed, "Blender approval restores in settings")
        app.auto_blender_check.button_pressed = false
        app._save_settings()
        check(not app.metadata.global_settings().get("auto_approve_blender_scripts", true) and app.metadata.global_settings().get("auto_approve_reloads", false), "disabling Blender approval leaves reload approval enabled")
        check(app.metadata.global_settings().get("auto_approve_reloads", false), "automatic approval persists for harness %d" % harness)
        var bridge = app.metadata.game_meta_dir(app.current_game).path_join("reload-test-bridge")
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bridge))
        app.agent.bridge_dir = ProjectSettings.globalize_path(bridge)
        var file = FileAccess.open(app.store.game_path(app.current_game).path_join("main.gd"), FileAccess.WRITE)
        file.store_string("extends Node\n")
        file.close()
        var request = FileAccess.open(bridge.path_join("request-auto.json"), FileAccess.WRITE)
        request.store_string(JSON.stringify({"id":"auto", "command":"reload_game", "args":{}}))
        request.close()
        app.agent._service_host_bridge()
        var reload_deadline = Time.get_ticks_msec() + 20000
        while not FileAccess.file_exists(bridge.path_join("response-auto.json")) and Time.get_ticks_msec() < reload_deadline:
            await process_frame
        check(app.runner.has_active_game() and app.agent.pending_reload.is_empty(), "automatic approval loads without waiting for harness %d" % harness)
        check(FileAccess.file_exists(bridge.path_join("response-auto.json")), "automatic approval returns tool response for harness %d" % harness)
        app._open_settings()
        app.auto_reload_check.button_pressed = false
        app._save_settings()
        app.agent.bridge_dir = ProjectSettings.globalize_path(bridge)
        request = FileAccess.open(bridge.path_join("request-manual.json"), FileAccess.WRITE)
        request.store_string(JSON.stringify({"id":"manual", "command":"reload_game", "args":{}}))
        request.close()
        app.agent._service_host_bridge()
        check(not app.agent.pending_reload.is_empty() and not FileAccess.file_exists(bridge.path_join("response-manual.json")), "turning automatic approval off restores the wait for harness %d" % harness)
        app.agent._clear_pending_reload()
        app._show_library()
    for harness_id in ["pi", "codex"]:
        await check_failed_blender_apply(app, harness_id)
    var prompt = preload("res://src/pi/pi_runtime_config.gd")._game_prompt()
    app._open_new_game()
    app.new_game_blender_check.button_pressed = true
    app.name_edit.text = "Blender opt-in"
    app._create_game()
    check(app.metadata.read_game(app.current_game).blender_enabled and app.tools.blender_enabled, "creation opt-in enables Blender")
    var codex_directory = app.metadata.game_meta_dir(app.current_game).path_join("codex")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(codex_directory))
    var session_file = FileAccess.open(codex_directory.path_join("session.json"), FileAccess.WRITE)
    session_file.store_string('{"session":"retained-thread"}')
    session_file.close()
    app._open_settings()
    app.game_blender_check.button_pressed = false
    app._save_settings()
    check(app.codex_session_dialog.visible and app.metadata.read_game(app.current_game).blender_enabled, "existing Codex tool registry requires explicit confirmation before changing availability")
    app._cancel_new_codex_session()
    check(FileAccess.file_exists(codex_directory.path_join("session.json")), "cancelling preserves the Codex session")
    app._save_settings()
    app._confirm_new_codex_session()
    check(not app.metadata.read_game(app.current_game).blender_enabled and not FileAccess.file_exists(codex_directory.path_join("session.json")), "confirming archives the old Codex registry and applies availability")
    var archives = DirAccess.get_files_at(codex_directory)
    check(archives.size() == 1 and archives[0].begins_with("session.previous-"), "Codex session reference remains archived")
    var existing_meta = app.metadata.read_game(app.current_game)
    existing_meta.erase("blender_enabled")
    app.metadata.write_game(app.current_game, existing_meta)
    app._open_settings()
    check(app.game_blender_check.button_pressed, "existing games without the setting retain Blender")
    app._show_library()
    app._open_new_game()
    check(not app.new_game_blender_check.button_pressed, "creation option resets for the next game")
    check(prompt.contains("successful headless test") and prompt.contains("before finishing"), "shared instructions require testing before reload and handoff")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)

func check_failed_blender_apply(app, harness_id: String) -> void:
    app._open_new_game()
    app.name_edit.text = "Blender transaction " + harness_id
    for i in app.harness_option.item_count:
        if str(app.harness_option.get_item_metadata(i)) == harness_id:
            app.harness_option.select(i)
    app.new_game_blender_check.button_pressed = true
    app._create_game()
    var original_metadata = app.metadata
    var failing = FailingMetadata.new()
    app.metadata = failing
    var session_path = failing.game_meta_dir(app.current_game).path_join("codex/session.json")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(session_path.get_base_dir()))
    var session_contents = '{"session":"transaction-retained-thread"}'
    var file = FileAccess.open(session_path, FileAccess.WRITE)
    file.store_string(session_contents)
    file.close()
    var modes = ["global", "commit"] if harness_id == "codex" else ["global", "credentials", "provider", "commit"]
    for mode in modes:
        app._open_settings()
        app.game_blender_check.button_pressed = false
        app.agent.bridge_dir = "transaction-runtime-fixture"
        var chat_before = app.transcript_view.get_parsed_text()
        failing.failure = mode
        failing.failures_seen = 0
        app._save_settings()
        check(app.codex_session_dialog.visible and failing.failures_seen == 0, "%s/%s asks before any settings writes" % [harness_id, mode])
        app._confirm_new_codex_session()
        check(failing.failures_seen == 1, "%s/%s injects the intended save failure" % [harness_id, mode])
        check(failing.read_game(app.current_game).blender_enabled and app.tools.blender_enabled, "%s/%s preserves Blender availability" % [harness_id, mode])
        check(FileAccess.get_file_as_string(session_path) == session_contents, "%s/%s preserves exact active Codex reference" % [harness_id, mode])
        check(DirAccess.get_files_at(session_path.get_base_dir()).size() == 1, "%s/%s leaves no stranded session archive" % [harness_id, mode])
        check(app.transcript_view.get_parsed_text() == chat_before, "%s/%s emits no false success transcript" % [harness_id, mode])
        check(app.agent.bridge_dir == "transaction-runtime-fixture", "%s/%s does not retire the active runtime" % [harness_id, mode])
        check(app.settings_dialog.visible, "%s/%s keeps settings open for retry" % [harness_id, mode])
        if mode == "commit":
            check(failing.archived_at_failure, "%s exercises rollback after actual archiving" % harness_id)
    failing.failure = ""
    app._save_settings()
    app._confirm_new_codex_session()
    check(not failing.read_game(app.current_game).blender_enabled and not FileAccess.file_exists(session_path), "%s retries successfully after storage recovery" % harness_id)
    check(app.agent.bridge_dir == "" and app.transcript_view.get_parsed_text().contains("Blender availability changed"), "%s announces and retires only after commit" % harness_id)
    app.metadata = original_metadata
    app._show_library()
    await process_frame
