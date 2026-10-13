extends SceneTree

var failures := 0
const ROUNDS := 5

func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value:
        failures += 1

func wait_reload_or_finish(app, timeout_ms: int = 10000) -> bool:
    var deadline = Time.get_ticks_msec() + timeout_ms
    while app.agent.busy and app.agent.pending_reload.is_empty() and Time.get_ticks_msec() < deadline:
        await process_frame
    return not app.agent.pending_reload.is_empty()

func wait_idle(app, timeout_ms: int = 10000) -> bool:
    var deadline = Time.get_ticks_msec() + timeout_ms
    while app.agent.busy and Time.get_ticks_msec() < deadline:
        await process_frame
    return not app.agent.busy

func _init() -> void:
    call_deferred("run")

func run() -> void:
    OS.set_environment("GAMESMITH_CLINE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-cline.mjs"))
    OS.set_environment("GAMESMITH_CURSOR_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-cursor.mjs"))
    var settings = MetadataStore.new().global_settings()
    settings.auto_approve_reloads = false
    MetadataStore.new().save_global_settings(settings)

    await exercise("Cline", 4)
    await exercise("Cursor", 5)

    OS.unset_environment("GAMESMITH_CLINE_BIN")
    OS.unset_environment("GAMESMITH_CURSOR_BIN")
    print("NATIVE RELOAD SMOKE: %d failure(s)" % failures)
    quit(1 if failures else 0)

func exercise(label: String, harness_index: int) -> void:
    for round_index in range(ROUNDS):
        var app = load("res://main.tscn").instantiate()
        root.add_child(app)
        await process_frame
        app.name_edit.text = "%s reload smoke %d" % [label, round_index]
        app.harness_option.select(harness_index)
        app._create_game()
        app.agent.send_player_request("reload")

        var reached = await wait_reload_or_finish(app)
        check(reached, "%s initial reload %d reaches player approval" % [label, round_index + 1])
        if reached:
            check(not app.runner.has_active_game(), "%s reload %d does not execute before approval" % [label, round_index + 1])
            app.agent.approve_reload()
            var settled = await wait_idle(app)
            check(settled, "%s approved reload %d settles" % [label, round_index + 1])
            check(settled and app.agent.last_error == "" and app.runner.has_active_game(), "%s approved reload %d completes" % [label, round_index + 1])
        else:
            check(false, "%s reload %d error: %s" % [label, round_index + 1, app.agent.last_error])
            if app.agent.busy:
                app.agent.cancel()
                await wait_idle(app, 3000)
        app.queue_free()
        await process_frame
