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
    for script in ["test_game_supervisor.gd", "test_game_process.gd", "test_game_watchdog.gd", "test_evidence.gd"]:
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
    var loaded = tools.reload_game()
    if not loaded.ok:
        push_error("FAIL: packaged runtime fixture could not load: " + str(loaded))
        quit(1)
        return
    var active = runner.active_game
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
    runner.queue_free()
    await process_frame
    print("PASS: exported runtime inspects and patches live properties without reloading")
    print("PASS: exported GameSmith.pck contains all harness adapters and the bundled Pi extension")
    quit(0)
