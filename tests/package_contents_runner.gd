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
    runner.queue_free()
    await process_frame
    print("PASS: exported runtime inspects and patches live properties without reloading")
    print("PASS: exported GameSmith.pck contains all harness adapters and the bundled Pi extension")
    quit(0)
