extends SceneTree

const EXTENSION_PATH := "res://tools/pi/gamesmith-extension.ts"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    for script in ["test_game_supervisor.gd", "test_game_process.gd"]:
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
    for module in ["workspace-paths.mjs", "model-capabilities.mjs", "diagnostic-delivery.mjs"]:
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
    print("PASS: exported GameSmith.pck contains the bundled Pi extension")
    quit(0)
