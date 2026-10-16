extends "res://src/pi/pi_rpc_session.gd"

func start(config: Dictionary) -> Dictionary:
    var label = str(config.get("label", "Command-code"))
    var had_blender_env = OS.has_environment("GAMESMITH_BLENDER_ENABLED")
    var old_blender_env = OS.get_environment("GAMESMITH_BLENDER_ENABLED")
    OS.set_environment("GAMESMITH_BLENDER_ENABLED", "1" if bool(config.get("blender_enabled", true)) else "0")
    var launched = OS.execute_with_pipe("node", PackedStringArray([str(config.worker), str(config.config_path)]), false)
    if had_blender_env:
        OS.set_environment("GAMESMITH_BLENDER_ENABLED", old_blender_env)
    else:
        OS.unset_environment("GAMESMITH_BLENDER_ENABLED")
    if launched.is_empty():
        return {"ok": false, "error": "Could not start " + label + " adapter. Install Node.js and the harness on PATH."}
    stdio = launched.get("stdio")
    stderr = launched.get("stderr")
    pid = int(launched.get("pid", -1))
    running = stdio != null and pid > 0
    process_mode = Node.PROCESS_MODE_ALWAYS
    return {"ok": running, "pid": pid, "error": label + " adapter did not provide usable pipes."}
