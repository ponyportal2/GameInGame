extends SceneTree

var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func _init() -> void:
    call_deferred("run")

func response(directory: String, id: String) -> Dictionary:
    var path = directory.path_join("response-" + id + ".json")
    var deadline = Time.get_ticks_msec() + 12000
    while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
        await process_frame
    return JsonStore.read_dict(path)

func request(directory: String, id: String, command: String, args: Dictionary = {}) -> void:
    check(JsonStore.write_dict(directory.path_join("request-" + id + ".json"), {"id": id, "command": command, "args": args}), "Bridge request written: " + command)

func run() -> void:
    var created = WorkspaceStore.new().create_game("ChatProcessIsolation")
    var file = FileAccess.open(created.path.path_join("main.gd"), FileAccess.WRITE)
    file.store_string("extends Node\nfunc _ready():\n\tprint('CHAT_TEST_READY')\n")
    file.close()
    var settings = {"provider": "custom", "model": "test", "custom_base_url": "http://127.0.0.1:1234/v1", "allow_rendered_tests": true}
    MetadataStore.new().save_global_settings(settings)
    var first = PiRuntimeConfig.prepare(created.name, created.path, settings, {}, {})
    check(first.ok, "First runtime prepared")
    request(first.bridge_dir, "ownership", "compaction_status")
    JsonStore.write_dict(first.bridge_dir.path_join("response-existing.json"), {"ok": true})
    var second = PiRuntimeConfig.prepare(created.name, created.path, settings, {}, {})
    check(second.ok and first.bridge_dir != second.bridge_dir, "Same-game runtimes have independent mailboxes")
    check(FileAccess.file_exists(first.bridge_dir.path_join("request-ownership.json")), "Preparing another runtime preserves the first request")
    check(FileAccess.file_exists(first.bridge_dir.path_join("response-existing.json")), "Preparing another runtime preserves the first response")
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    app.agent.bridge_dir = first.bridge_dir
    app.agent.auto_compaction_failed_operation = app.agent.operation_id
    var idle = PiAgentController.new()
    root.add_child(idle)
    idle.configure(created.name, app.tools)
    idle.bridge_dir = second.bridge_dir
    request(second.bridge_dir, "ownership", "compaction_status")
    var owned: Dictionary = await response(first.bridge_dir, "ownership")
    var other: Dictionary = await response(second.bridge_dir, "ownership")
    check(owned.get("blocked", false) and not other.get("blocked", true), "Identical call IDs return only to their owning controller")
    check(paused and not app.runner.has_active_game(), "Chat-first host is paused without an active game")
    request(first.bridge_dir, "start", "start_test_game", {"mode": "rendered"})
    var started: Dictionary = await response(first.bridge_dir, "start")
    check(started.get("ok", false), "Rendered test responds while chat is paused")
    if started.get("ok", false):
        var supervisor = app.tools.tests()
        var deadline = Time.get_ticks_msec() + 12000
        var state: Dictionary = supervisor.status(started.run_id)
        while state.get("state") == "starting" and Time.get_ticks_msec() < deadline:
            await process_frame
            state = supervisor.status(started.run_id)
        check(state.get("state") == "running", "Rendered child runs while host stays in chat")
        check(supervisor.runs.size() == 1, "Idle second controller does not duplicate test launch")
        check(not FileAccess.file_exists(second.bridge_dir.path_join("response-start.json")), "Test response stays in requesting mailbox")
        request(first.bridge_dir, "stop", "stop_test_game", {"run_id": started.run_id})
        var stopped: Dictionary = await response(first.bridge_dir, "stop")
        check(stopped.get("state") == "exited", "Stop response arrives while chat is paused")
        check(not app.runner.has_active_game(), "Testing never starts the player's live game")
    idle.queue_free()
    app.queue_free()
    await process_frame
    paused = false
    print("CHAT BRIDGE TESTS: ", passed, " passed, ", failed, " failed")
    quit(0 if failed == 0 else 1)
