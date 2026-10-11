extends SceneTree

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
    app.name_edit.text = "Pi fixture"
    app.harness_option.select(0)
    app._create_game()
    app._open_settings()
    check(not app.provider_option.disabled and app.model_edit.editable and app.compaction_auto_spin.editable, "Pi controls restore for a Pi game")
    check(app.metadata.read_game(app.current_game).get("harness") == "pi", "Pi selection persists")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
