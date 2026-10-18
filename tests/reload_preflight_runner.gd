extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
const Supervisor = preload("res://src/core/test_game_supervisor.gd")
var passed := 0
var failed := 0
var workspace := "user://games/Reload preflight"

func _init() -> void:
    call_deferred("run")

func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if value: passed += 1
    else: failed += 1

func put(source: String, file: String = "main.gd") -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    var out = FileAccess.open(workspace.path_join(file), FileAccess.WRITE)
    out.store_string(source)
    out.close()

func run() -> void:
    var runner = Runner.new()
    root.add_child(runner)
    check(runner.has_method("checked_reload"), "reload has mandatory asynchronous preflight")
    if not runner.has_method("checked_reload"):
        runner.free()
        quit(1)
        return
    put("extends Node\nvar answer = 1\n")
    check(runner.load_game(workspace).ok, "initial live fixture")
    var old = runner.active_game
    var supervisor = Supervisor.new()
    root.add_child(supervisor)
    var existing = supervisor.start(workspace)
    check(existing.ok, "independent agent test starts")
    put("extends Node\nvar answer = 2\n")
    var result: Dictionary = await runner.checked_reload(workspace)
    check(result.ok and runner.active_game.answer == 2, "passing preflight loads current code")
    check(result.preflight.process_ticks_completed >= 4 and result.preflight.physics_ticks_completed >= 3, "preflight reports completed process and physics ticks")
    check(result.preflight.cleanup.state == "exited" and result.preflight.cleanup.stop_method == "graceful", "successful preflight exits gracefully")
    check(not result.preflight.cleanup.has("action_result"), "preflight status excludes supervisor-owned action result")
    var decoded = JSON.parse_string(JSON.stringify(result))
    check(decoded is Dictionary and decoded.preflight.process_ticks_completed >= 4, "complete reload result survives JSON round trip")
    check(supervisor.status(existing.run_id).state in ["starting", "running"], "preflight preserves independent agent test")

    var errors = {
        "process": "func _process(_d):\n\tget_node(\"MissingProcess\")\n",
        "physics": "func _physics_process(_d):\n\tget_node(\"MissingPhysics\")\n",
        "deferred": "func _ready():\n\tcall_deferred(\"broken\")\nfunc broken():\n\tget_node(\"MissingDeferred\")\n",
        "cleanup": "func _exit_tree():\n\tpush_error(\"Broken cleanup\")\n",
        "cleanup_hang": "func _exit_tree():\n\twhile true: pass\n",
        "startup": "func _ready():\n\tget_node(\"MissingStartup\")\n",
        "compile": "func broken(:\n",
        "early_exit": "func _ready():\n\tget_tree().quit(0)\n",
    }
    for label in errors:
        old = runner.active_game
        put("extends Node\n" + errors[label])
        result = await runner.checked_reload(workspace)
        check(not result.ok and runner.active_game == old, label + " rejection preserves live identity")
        check(not result.live_game_modified and result.preflight.cleanup.state == "exited", label + " rejection cleans owned child")
        if label in ["process", "physics", "deferred"]:
            check(not result.preflight.get("diagnostics", {}).is_empty(), label + " returns diagnostics")

    put("extends Node\nfunc _process(_d):\n\twhile true: pass\n")
    old = runner.active_game
    runner.preflight_timeout_ms = 1200
    result = await runner.checked_reload(workspace)
    check(not result.ok and result.preflight.reason == "timeout" and runner.active_game == old, "hung processing times out without touching live")
    check(result.preflight.cleanup.state == "exited", "hung child is reaped")
    runner.preflight_timeout_ms = 15000

    put("extends Node\nvar answer = 3\n")
    var cancel_at = Time.get_ticks_msec() + 150
    result = await runner.checked_reload(workspace, func(): return Time.get_ticks_msec() >= cancel_at)
    check(not result.ok and result.preflight.reason == "cancelled" and runner.active_game == old, "cancelled reload leaves live unchanged")
    check(result.preflight.cleanup.state == "exited", "cancelled child is reaped")

    # A passing isolated copy does not replace the host's synchronous checks.
    put("extends Node\nfunc _ready():\n\tif not 'preflights' in OS.get_user_data_dir():\n\t\tget_node(\"MissingOnlyInHost\")\n")
    result = await runner.checked_reload(workspace)
    check(not result.ok and result.preflight.ok and result.live_attempted and runner.active_game == old, "host startup check still rejects after passing preflight")
    check(result.live_game_modified == null, "failed live attempt does not promise rollback")

    put("extends Node\nvar answer = 4\n")
    var added_dependency = "helper_%d.gd" % Time.get_ticks_usec()
    check(not FileAccess.file_exists(workspace.path_join(added_dependency)), "source-change fixture begins without added dependency")
    var changed := [false]
    result = await runner.checked_reload(workspace, func():
        if not changed[0]:
            changed[0] = true
            put("extends Node\nvar unused = 1\n", added_dependency)
        return false)
    if result.get("reason") != "code_changed": print("Source-change rejection: ", result.get("reason"), "; preflight: ", result.get("preflight", {}).get("reason"))
    check(not result.ok and result.get("reason") == "code_changed" and runner.active_game == old, "new code dependency invalidates preflight")

    put("extends Node\nvar answer = 5\n")
    # A second request must not race the first request into live application.
    var tools = GameTools.new(workspace, runner)
    var pending = tools.reload_game()
    check(pending.get("pending", false), "tool reload does not block host")
    result = await runner.checked_reload(workspace)
    check(not result.ok and result.reason == "reload_in_progress", "concurrent reload rejected")
    tools.cancel_reload()
    result = await tools.wait_reload(pending)
    check(not result.ok and runner.active_game == old, "tool cancellation prevents later application")

    # Leaving a game during preflight must reap its owned process too.
    var disposable = Runner.new()
    root.add_child(disposable)
    var disposable_tools = GameTools.new(workspace, disposable)
    var abandoned = disposable_tools.reload_game()
    var owned_pid = disposable.get_child(0).runs.values()[0].pid
    disposable.queue_free()
    await process_frame
    await process_frame
    result = await disposable_tools.wait_reload(abandoned)
    check(not result.ok and not OS.is_process_running(owned_pid), "runner teardown stops its preflight process")
    supervisor.request_stop(existing.run_id)
    while supervisor.status(existing.run_id).state != "exited":
        await process_frame
    supervisor.free()
    runner.free()
    print("Reload preflight: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)
