extends SceneTree

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
    var prompt = preload("res://src/pi/pi_runtime_config.gd")._game_prompt()
    check(prompt.contains("successful headless test") and prompt.contains("before finishing"), "shared instructions require testing before reload and handoff")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
