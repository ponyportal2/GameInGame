extends SceneTree

const EXTENSION_PATH := "res://tools/pi/gamesmith-extension.ts"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
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
    print("PASS: exported GameSmith.pck contains all harness adapters and the bundled Pi extension")
    quit(0)
