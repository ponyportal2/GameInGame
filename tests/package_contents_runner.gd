extends SceneTree

const EXTENSION_PATH := "res://tools/pi/gamesmith-extension.ts"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not ResourceLoader.exists("res://src/core/chat_history.gd"):
        push_error("FAIL: exported GameSmith.pck is missing visible chat history")
        quit(1)
        return
    if not ResourceLoader.exists("res://src/core/image_generation.gd"):
        push_error("FAIL: exported GameSmith.pck is missing image generation")
        quit(1)
        return
    for module in ["jobs.mjs", "ownership.mjs", "bootstrap.py", "guide.md", "example.py"]:
        if not FileAccess.file_exists("res://tools/blender/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Blender " + module)
            quit(1)
            return
    if not ResourceLoader.exists("res://src/core/blender_supervisor.gd") or not ResourceLoader.exists("res://src/core/game_assets.gd"):
        push_error("FAIL: exported GameSmith.pck is missing Blender supervisor")
        quit(1)
        return
    for module in ["ownership.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/agent/" + module):
            push_error("FAIL: exported GameSmith.pck is missing " + module)
            quit(1)
            return
    var inventory = preload("res://src/agent/harness_inventory.gd")
    for harness in inventory.all():
        if not ResourceLoader.exists("res://" + str(harness.controller)):
            push_error("FAIL: missing controller " + str(harness.id))
            quit(1)
            return
        var assembled = inventory.assemble_runtime(harness.id, "user://package-runtime/" + str(harness.id))
        if not assembled.ok:
            push_error("FAIL: " + str(assembled.error))
            quit(1)
            return
    for script in ["workspace_ui.gd", "settings_ui.gd", "theme_factory.gd"]:
        if not ResourceLoader.exists("res://src/ui/" + script):
            push_error("FAIL: exported GameSmith.pck is missing " + script)
            quit(1)
            return
    for script in ["test_game_supervisor.gd", "test_game_process.gd", "test_game_watchdog.gd", "test_evidence.gd", "reload_preflight.gd", "runtime_children.gd"]:
        if not ResourceLoader.exists("res://src/core/" + script):
            push_error("FAIL: exported GameSmith.pck is missing " + script)
            quit(1)
            return
    if not ResourceLoader.exists("res://src/core/script_load_policy.gd"):
        push_error("FAIL: exported GameSmith.pck is missing the script loading policy")
        quit(1)
        return
    if not ResourceLoader.exists("res://src/core/runtime_log_reader.gd"):
        push_error("FAIL: exported GameSmith.pck is missing the runtime diagnostics reader")
        quit(1)
        return
    for module in ["workspace-paths.mjs", "model-capabilities.mjs", "diagnostic-delivery.mjs", "empty-response-retry.mjs"]:
        if not FileAccess.file_exists("res://tools/pi/" + module):
            push_error("FAIL: exported GameSmith.pck is missing " + module)
            quit(1)
            return
    if not FileAccess.file_exists(EXTENSION_PATH):
        push_error("FAIL: exported GameSmith.pck is missing " + EXTENSION_PATH)
        quit(1)
        return
    var source = FileAccess.get_file_as_string(EXTENSION_PATH)
    if source.strip_edges() == "":
        push_error("FAIL: exported Pi extension is empty")
        quit(1)
        return
    # Execute the new capability from the shipped PCK, not just a source check.
    var runner = preload("res://src/core/game_runner.gd").new()
    root.add_child(runner)
    var tools = preload("res://src/core/game_tools.gd").new("user://package-live-properties", runner)
    tools.write_file("main.gd", "extends Node2D\nvar speed = 80.0\nvar health = 43\n")
    var loaded = await tools.wait_reload(tools.reload_game())
    if not loaded.ok:
        push_error("FAIL: packaged runtime fixture could not load: " + str(loaded))
        quit(1)
        return
    if loaded.preflight.process_ticks_completed < 4 or loaded.preflight.physics_ticks_completed < 3 or loaded.preflight.cleanup.state != "exited":
        push_error("FAIL: packaged reload did not complete isolated smoke execution and cleanup")
        quit(1)
        return
    var startup_smoke: Dictionary = loaded.preflight.cleanup.get("startup_smoke", {})
    if not startup_smoke.get("ok", false) or startup_smoke.get("process_ticks_completed", 0) < 4 or startup_smoke.get("physics_ticks_completed", 0) < 3:
        push_error("FAIL: packaged detached startup skipped automatic smoke execution")
        quit(1)
        return
    print("PASS: packaged detached startup completes smoke ticks before running")
    var active = runner.active_game
    tools.write_file("main.gd", "extends Node2D\nfunc _physics_process(_d):\n    get_node(\"MissingPackagedPhysics\")\n")
    var preflight_rejected = await tools.wait_reload(tools.reload_game())
    if preflight_rejected.ok or not preflight_rejected.has("diagnostics") or preflight_rejected.live_attempted or runner.active_game != active:
        push_error("FAIL: packaged reload admitted a physics error or lost diagnostics")
        quit(1)
        return
    print("PASS: packaged reload runs process/physics ticks and rejects runtime errors without replacing live game")
    var inspected = tools.execute("inspect_runtime", {"depth": 0, "properties": ["speed", "health"]})
    if not inspected.ok or inspected.nodes.size() != 1:
        push_error("FAIL: packaged runtime inspection")
        quit(1)
        return
    var patched = tools.execute("set_properties", {"targets": [inspected.nodes[0].handle], "values": {"speed": 120.0}})
    if not patched.ok or runner.active_game != active or active.speed != 120.0 or active.health != 43:
        push_error("FAIL: packaged live patch failed or reset unrelated state")
        quit(1)
        return
    for i in range(200):
        var wall = Polygon2D.new()
        wall.name = "Wall%d" % i
        wall.color = Color(0.09, 0.11, 0.17)
        active.add_child(wall)
    var handles: Array = []
    for offset in [0, 64, 128, 192]:
        var page = tools.execute("inspect_runtime", {"class": "Polygon2D", "properties": ["color"], "limit": 64, "offset": offset})
        if not page.ok or JSON.stringify({"content": [{"type": "text", "text": JSON.stringify(page)}]}).to_utf8_buffer().size() >= 24000 or page.nodes[0].has("available_properties") or page.has_more != (offset < 192):
            push_error("FAIL: packaged compact inspection/pagination")
            quit(1)
            return
        for entry in page.nodes: handles.append(entry.handle)
    if handles.size() != 200:
        quit(1)
        return
    var rejected = tools.execute("set_properties", {"targets": handles.slice(0, 100), "values": {"name": "wall"}})
    if rejected.ok or rejected.get("writes_started", true) or active.get_node("Wall0").name != &"Wall0":
        push_error("Packaged mutation budget did not reject before writing")
        quit(1)
        return
    for offset in [0, 50, 100, 150]:
        var patch = tools.execute("set_properties", {"targets": handles.slice(offset, offset + 50), "values": {"color": {"type": "Color", "r": 0.3, "g": 0.38, "b": 0.5, "a": 1}}})
        if not patch.ok or patch.changed != 50 or not patch.temporary or runner.active_game != active or active.health != 43:
            push_error("FAIL: packaged wall patch")
            quit(1)
            return
    if not is_equal_approx(active.get_node("Wall199").color.r, 0.3):
        quit(1)
        return
    print("PASS: packaged compact wall inspection pages and recolors 200 live nodes")
    # The deliberately broken disk candidate above must not seed injection tests.
    tools.write_file("main.gd", "extends Node2D\n")
    tools.write_file("ability.gd", "extends Node\nvar power = 0.0\nvar ready_power = 0.0\nfunc _ready():\n\tready_power = power\n")
    var parent = tools.execute("inspect_runtime", {"depth": 0}).nodes[0].handle
    var controller = preload("res://src/agent/opencode_agent_controller.gd").new()
    root.add_child(controller)
    controller.set_process(false)
    controller.tools = tools
    controller.bridge_dir = ProjectSettings.globalize_path("user://packaged-child-approval")
    DirAccess.make_dir_recursive_absolute(controller.bridge_dir)
    controller._dispatch_host_request({"id": "child", "command": "add_runtime_child", "args": {"parent": parent, "candidate_path": ".", "name": "PackagedAbility", "script_path": "ability.gd", "properties": {"power": 9.0}}}, controller.bridge_dir)
    if controller.pending_reload.is_empty() or runner.active_game.has_node("PackagedAbility"):
        push_error("FAIL: packaged child code bypassed player consent")
        quit(1)
        return
    controller.approve_reload()
    var response_path = controller.bridge_dir.path_join("response-child.json")
    var deadline = Time.get_ticks_msec() + 25000
    while not FileAccess.file_exists(response_path) and Time.get_ticks_msec() < deadline:
        await process_frame
    var added = JsonStore.read_dict(response_path, {"ok": false})
    if not added.ok or runner.active_game.get_node("PackagedAbility").ready_power != 9.0 or not added.preflight.ok:
        push_error("FAIL: packaged late-child preflight/insertion " + str(added))
        quit(1)
        return
    var removed = await tools.wait_reload(tools.execute("remove_runtime_child", {"target": added.handle}))
    if not removed.ok or runner.active_game.has_node("PackagedAbility"):
        push_error("FAIL: packaged injected child removal")
        quit(1)
        return
    print("PASS: packaged runtime preflights late insertion and removes only its injected child")
    print("PASS: packaged child code requires player approval before preflight and live application")
    tools.write_file("mouse_ability.gd", "extends Node\nvar pressed_count = 0\nfunc _input(event):\n\tif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:\n\t\tpressed_count += 1\n")
    var started = tools.execute("start_test_game", {"mode": "headless"})
    var test_id = str(started.get("run_id", ""))
    deadline = Time.get_ticks_msec() + 20000
    while tools.tests().status(test_id).get("state") == "starting" and Time.get_ticks_msec() < deadline: await process_frame
    var injected = await _bridge_action(controller, "injection", {"run_id": test_id, "action": "inject_child", "candidate_path": ".", "name": "MouseAbility", "script_path": "mouse_ability.gd"})
    var pressed = await _bridge_action(controller, "press", {"run_id": test_id, "action": "mouse_button", "button_index": 3, "pressed": true})
    await _bridge_action(controller, "release", {"run_id": test_id, "action": "mouse_button", "button_index": 3, "pressed": false})
    var mouse_inspected = await _bridge_action(controller, "inspect", {"run_id": test_id, "action": "inspect", "path": "MouseAbility", "properties": ["pressed_count"]})
    if not injected.get("ok", false) or injected.get("pending", true) or injected.get("physics_ticks_completed", 0) < 3 or not pressed.get("ok", false) or mouse_inspected.get("properties", {}).get("pressed_count") != "1" or runner.active_game.has_node("MouseAbility"):
        push_error("FAIL: packaged detached injection/mouse/completion: " + str([injected, pressed, mouse_inspected]))
        tools.execute("stop_test_game", {"run_id": test_id})
        quit(1)
        return
    tools.execute("stop_test_game", {"run_id": test_id})
    deadline = Time.get_ticks_msec() + 10000
    while tools.tests().status(test_id).get("state") != "exited" and Time.get_ticks_msec() < deadline: await process_frame
    if tools.tests().status(test_id).get("stop_method") != "graceful":
        push_error("FAIL: packaged detached workflow shutdown")
        quit(1)
        return
    print("PASS: packaged detached late injection, real middle mouse and same-call action results preserve live game")
    controller.free()
    runner.queue_free()
    await process_frame
    print("PASS: exported runtime inspects and patches live properties without reloading")
    print("PASS: exported GameSmith.pck contains all harness adapters and the bundled Pi extension")
    quit(0)

func _bridge_action(controller: Node, id: String, args: Dictionary) -> Dictionary:
    # The host answers "pending" when an action needs more than one frame, so a
    # caller polls with the returned action_id exactly like the agent does. A
    # single call only proves the same-call fast path on an idle machine.
    var result: Dictionary = await _bridge_call(controller, id, args)
    var attempts := 0
    var deadline = Time.get_ticks_msec() + 15000
    while result.get("pending", false) and attempts < 200 and Time.get_ticks_msec() < deadline:
        attempts += 1
        await create_timer(0.05).timeout
        result = await _bridge_call(controller, "%s-poll-%d" % [id, attempts], {"run_id": args.get("run_id", ""), "action": "poll", "action_id": result.get("action_id", "")})
    return result

func _bridge_call(controller: Node, id: String, args: Dictionary) -> Dictionary:
    controller._dispatch_host_request({"id": id, "command": "test_game_action", "args": args}, controller.bridge_dir)
    var path = controller.bridge_dir.path_join("response-" + id + ".json")
    var deadline = Time.get_ticks_msec() + 10000
    while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
        controller._service_pending_test_commands()
        await process_frame
    return JsonStore.read_dict(path, {"ok": false})
