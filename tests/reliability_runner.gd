extends SceneTree

const Store = preload("res://src/core/workspace_store.gd")
const Metadata = preload("res://src/core/metadata_store.gd")
const Runner = preload("res://src/core/game_runner.gd")
const Controller = preload("res://src/agent/pi_agent_controller.gd")
const Rpc = preload("res://src/pi/pi_rpc_session.gd")
const Json = preload("res://src/core/json_store.gd")
const Config = preload("res://src/pi/pi_runtime_config.gd")
var passed = 0
var failures = 0

class PendingRpc:
    extends Node
    signal record_received(record: Dictionary)
    signal stderr_line(text: String)
    signal process_stopped(message: String)
    var running = true
    var commands: Array[String] = []
    var settle_prompt = false
    func command(record: Dictionary) -> Dictionary:
        commands.append(record.type)
        if record.type == "get_state":
            return {"success": true, "data": {"model": {"provider": "gamesmith", "id": "test", "reasoning": false}, "thinkingLevel": "off", "sessionName": "Cancel Test"}}
        if record.type == "prompt" and settle_prompt:
            call_deferred("_settle")
        if record.type in ["set_auto_compaction", "get_session_stats", "prompt"]:
            return {"success": true, "data": {}}
        if record.type == "get_last_assistant_text":
            return {"success": true, "data": {"text": "Resumed."}}
        while running:
            await get_tree().process_frame
        return {"success": false, "error": "Cancelled"}
    func _settle() -> void:
        record_received.emit({"type": "turn_start"})
        record_received.emit({"type": "agent_settled"})
    func retire() -> void:
        running = false
        if is_inside_tree():
            await get_tree().process_frame
        queue_free()

func _init() -> void:
    call_deferred("run")

func check(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAIL: " + label)

func put(path: String, text: String) -> void:
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()

func run() -> void:
    await test_fallback()
    await test_startup_and_dependencies()
    await test_rename()
    await test_cancel()
    await test_persistence()
    await test_capabilities()
    print("RELIABILITY TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

func test_fallback() -> void:
    var store = Store.new()
    var created = store.create_game("Fallback Regression")
    check(created.ok, "creates fallback fixture")
    var good = "extends Node\nvar marker = 'working'\n"
    put(created.path.path_join("main.gd"), good)
    put(created.path.path_join("keep.txt"), "snapshot content")
    check(store.save_working_snapshot(created.name), "saves initial working snapshot")
    var snapshot = store.metadata.snapshot_dir(created.name)
    var before_meta = store.metadata.read_game(created.name)
    put(created.path.path_join("main.gd"), "extends Node\nfunc broken(:\n")
    put(created.path.path_join("keep.txt"), "broken workspace content")
    put(snapshot + ".previous", "blocked promotion")
    check(not store.save_working_snapshot(created.name), "failed snapshot promotion is reported")
    check(FileAccess.get_file_as_string(snapshot.path_join("main.gd")) == good, "failed snapshot promotion preserves previous working files")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(snapshot + ".previous"))
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    check(app.runner.active_game.marker == "working", "fallback runs the last working game")
    check(FileAccess.get_file_as_string(snapshot.path_join("main.gd")) == good, "fallback preserves working snapshot source")
    check(FileAccess.get_file_as_string(snapshot.path_join("keep.txt")) == "snapshot content", "fallback preserves all snapshot files")
    check(store.metadata.read_game(created.name) == before_meta, "fallback does not promote broken workspace metadata")
    app._show_library()
    await process_frame
    app._open_game(created.name)
    check(app.runner.has_active_game(), "fallback still rescues the next launch")
    app.queue_free()
    await process_frame
    store.delete_game(created.name)

func test_startup_and_dependencies() -> void:
    var store = Store.new()
    var created = store.create_game("Reload Regression")
    var main = created.path.path_join("main.gd")
    var helper = created.path.path_join("helper.gd")
    put(helper, "extends RefCounted\nfunc value(): return 41\n")
    var source = "extends Node\nconst H = preload('helper.gd')\nvar answer = 0\nfunc _ready(): answer = H.new().value()\n"
    put(main, source)
    put(created.path.path_join("unused-draft.gd"), "extends Node\nfunc broken(:\n")
    var runner = Runner.new()
    root.add_child(runner)
    check(runner.load_game(created.path).ok and runner.active_game.answer == 41, "loads initial dependency value")
    var old = runner.active_game
    var old_version = runner.runtime_log.load_version
    var old_helper = ResourceLoader.get_cached_ref(helper)
    put(helper, "extends RefCounted\nfunc value(): return 99\n")
    put(main, "extends Node\nfunc _ready():\n    var values = []\n    print(values[123])\n")
    var rejected = runner.load_game(created.path)
    check(not rejected.ok, "rejects runtime failure in candidate _ready")
    check(runner.active_game == old and old.is_inside_tree(), "startup failure keeps previous game running")
    check(runner.runtime_log.load_version == old_version, "startup failure does not publish a successful load version")
    check(ResourceLoader.get_cached_ref(helper) == old_helper, "startup rejection restores dependency cache")
    put(main, source)
    check(runner.load_game(created.path).ok, "reloads after startup error is fixed")
    check(runner.active_game.answer == 99, "reload uses edited dependency instead of cached code")
    put(main, "extends Node\nconst H = preload('%s')\nvar answer = 0\nfunc _ready(): answer = H.new().value()\n" % helper)
    check(runner.load_game(created.path).ok and runner.active_game.answer == 99, "preloaded dependency uses edited source too")
    put(helper, "extends RefCounted\nfunc value(): return 123\n")
    check(runner.load_game(created.path).ok and runner.active_game.answer == 123, "subsequent dependency reloads also use current source")
    old = runner.active_game
    put(helper, "extends RefCounted\nfunc broken(:\n")
    check(not runner.load_game(created.path).ok and runner.active_game == old, "broken dependency preserves previous game")
    put(main, "extends Node\nvar answer = 456\n")
    check(runner.load_game(created.path).ok and runner.active_game.answer == 456, "formerly used broken helper does not reject a candidate that no longer uses it")
    runner.queue_free()
    await process_frame
    store.delete_game(created.name)

func test_rename() -> void:
    var store = Store.new()
    var created = store.create_game("Rename Runtime Regression")
    put(created.path.path_join("main.gd"), "extends Node\n")
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    var rpc = PendingRpc.new()
    var diagnostic_session = app.runner.runtime_log.session_id
    app.agent.add_child(rpc)
    app.agent.rpc = rpc
    rpc.record_received.connect(app.agent._on_pi_record)
    app.agent.bridge_dir = "old bridge"
    app.agent.busy = true
    app._set_chat_busy_controls(true)
    app.rename_target = created.name
    app.rename_edit.text = "Renamed Runtime Regression"
    app._rename_game()
    check(app.current_game == created.name and rpc.running, "rename is blocked during an agent turn")
    check(app.rename_button.disabled, "rename control is disabled while busy")
    app.agent.busy = false
    app._rename_game()
    check(app.current_game == "Renamed Runtime Regression", "idle game rename succeeds")
    check(app.agent.rpc == null and app.agent.bridge_dir == "" and not rpc.running, "rename shuts down runtime and clears stale bridge")
    check(app.agent.game_name == app.current_game and app.tools.workspace == store.game_path(app.current_game), "rename rebinds controller and workspace")
    app.runner.runtime_log.capture("warning", "godot_error", "production rename diagnostic")
    check(app.runner.runtime_log.session_id == diagnostic_session and app.runner.runtime_log.read_text().contains("production rename diagnostic"), "production rename handler preserves and rebinds the diagnostic session")
    var collision = store.create_game("Rename Collision")
    app.rename_target = app.current_game
    app.rename_edit.text = collision.name
    app._rename_game()
    app.runner.runtime_log.capture("warning", "godot_error", "after failed rename")
    check(app.current_game == "Renamed Runtime Regression" and app.runner.runtime_log.session_id == diagnostic_session and app.runner.runtime_log.read_text().contains("after failed rename"), "failed production rename resumes the existing writer")
    var new_name = app.current_game
    app.queue_free()
    await process_frame
    store.delete_game(new_name)
    store.delete_game(collision.name)

func test_cancel() -> void:
    var store = Store.new()
    var created = store.create_game("Cancel Test")
    put(created.path.path_join("main.gd"), "extends Node\n")
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(created.name)
    app._set_chat_visible(true)
    var rpc = PendingRpc.new()
    app.agent.add_child(rpc)
    app.agent.rpc = rpc
    app.agent.runtime_config = {"provider": "gamesmith", "model": "test"}
    var completion = {"count": 0}
    app.agent.finished.connect(func(_ok): completion.count += 1)
    app.chat_input.text = "tell me something"
    app._send_chat()
    check(app.agent.busy and not app.stop_button.disabled, "Stop is available during a pending request")
    put(created.path.path_join("already-edited.txt"), "keep this edit")
    app.stop_button.pressed.emit()
    check(not app.agent.busy and app.chat_input.editable and not app.library_button.disabled, "Stop restores composer and navigation immediately")
    check(app.agent.rpc == null and not rpc.running, "Stop disconnects pending runtime")
    var resumed_rpc = PendingRpc.new()
    resumed_rpc.settle_prompt = true
    app.agent.add_child(resumed_rpc)
    app.agent.rpc = resumed_rpc
    resumed_rpc.record_received.connect(app.agent._on_pi_record)
    app.chat_input.text = "tell me something immediately after Stop"
    app._send_chat()
    for _frame in 5:
        await process_frame
    check(not app.agent.busy, "immediate request after Stop settles without interference from cancelled request")
    check(completion.count == 2, "cancelled request and immediate retry each complete exactly once")
    check(FileAccess.get_file_as_string(created.path.path_join("already-edited.txt")) == "keep this edit", "Stop preserves existing workspace edits")
    app.agent.restart_runtime()
    rpc = PendingRpc.new()
    app.agent.add_child(rpc)
    app.agent.rpc = rpc
    app._compact_now_from_settings()
    check(app.agent.busy and not app.stop_button.disabled, "Stop is available during manual compaction")
    app._stop_agent()
    await process_frame
    await process_frame
    check(not app.agent.busy and app.chat_input.editable, "cancelled compaction restores controls")
    check("cancelled" in app.compaction_status_label.text.to_lower(), "cancelled compaction is reported explicitly")
    app.queue_free()
    await process_frame
    store.delete_game(created.name)

func test_persistence() -> void:
    var dir = "user://atomic-test"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    var path = dir.path_join("state.json")
    check(Json.write_dict(path, {"value": "old"}), "writes initial atomic JSON")
    check(Json.write_dict(path, {"value": "new"}) and Json.read_dict(path).value == "new", "atomically replaces existing JSON")
    if OS.get_name() == "Windows":
        FileAccess.set_read_only_attribute(ProjectSettings.globalize_path(path), true)
        check(not Json.write_dict(path, {"value": "lost"}), "read-only destination reports failed JSON replacement")
        check(Json.read_dict(path).value == "new", "failed replacement preserves the original destination bytes")
        FileAccess.set_read_only_attribute(ProjectSettings.globalize_path(path), false)
    check(not Json.write_dict(dir, {"value": "bad"}), "failed JSON replacement is reported")
    check(Json.read_dict(path).value == "new", "failed replacement leaves existing state intact")
    check(DirAccess.open(dir).get_files().size() == 1, "failed JSON replacement cleans temporary files")
    var metadata = Metadata.new()
    var previous = metadata.credentials()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Metadata.CREDENTIALS_PATH))
    DirAccess.make_dir_absolute(ProjectSettings.globalize_path(Metadata.CREDENTIALS_PATH))
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_settings()
    app._save_settings()
    check(app.settings_dialog.visible, "settings overlay remains open after persistence failure")
    check("provider credentials" in app.compaction_status_label.text and not app.toast_label.text == "Settings saved.", "UI identifies failed writes instead of claiming settings saved")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Metadata.CREDENTIALS_PATH))
    metadata.save_credentials(previous)
    app.queue_free()
    await process_frame

func test_capabilities() -> void:
    var store = Store.new()
    var created = store.create_game("Unknown Model Regression")
    var settings = {"provider": "custom", "model": "unknown-model", "custom_base_url": "http://127.0.0.1:1/v1", "compaction_auto_tokens": 2000000, "compaction_keep_recent_tokens": 500000, "reasoning_effort": "high"}
    var config = Config.prepare(created.name, created.path, settings, {}, {})
    check(config.ok, "prepares unknown custom model")
    var model_path = config.agent_dir.path_join("models.json")
    var model = Json.read_dict(model_path).providers.gamesmith.models[0]
    check(not model.reasoning, "unknown model does not claim reasoning support")
    check(model.contextWindow == Config.UNKNOWN_CONTEXT_BUDGET and model.maxTokens == Config.UNKNOWN_OUTPUT_BUDGET, "unknown model uses explicit conservative budgets")
    settings.compaction_auto_tokens = 1
    settings.compaction_keep_recent_tokens = 1000
    Config.prepare(created.name, created.path, settings, {}, {})
    check(Json.read_dict(model_path).providers.gamesmith.models[0] == model, "compaction controls never change declared model capabilities")
    var agent = Controller.new()
    root.add_child(agent)
    agent.configure(created.name, preload("res://src/core/game_tools.gd").new(created.path))
    agent.runtime_config = {"provider": "gamesmith", "model": "test", "thinking": "high"}
    var rpc = PendingRpc.new()
    agent.add_child(rpc)
    agent.rpc = rpc
    check((await agent._sync_runtime_state(rpc)).ok, "syncs a nonreasoning model without unsupported thinking")
    check(not "set_thinking_level" in rpc.commands, "unsupported reasoning setting is not sent to Pi")
    agent.queue_free()
    await process_frame
    store.delete_game(created.name)
