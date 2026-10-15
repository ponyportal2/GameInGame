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
    for module in ["worker.mjs", "server.mjs", "policy.mjs", "gamesmith.ts", "host-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/command-code/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Command-code " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "events.mjs", "protocol.mjs", "gamesmith.mjs", "mcp.mjs", "host-tools.mjs", "workspace-paths.mjs"]:
        if not FileAccess.file_exists("res://tools/opencode/" + module):
            push_error("FAIL: exported GameSmith.pck is missing OpenCode " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "tools.mjs", "host-tools.mjs", "workspace-paths.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/codex/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Codex " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "approval.mjs", "workspace-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/cline/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Cline " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "approval.mjs", "workspace-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/cursor/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Cursor " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "approval.mjs", "workspace-tools.mjs", "workspace-paths.mjs", "host-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/grok-build/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Grok Build " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "hook.mjs", "workspace-tools.mjs", "workspace-paths.mjs", "host-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/agy/" + module):
            push_error("FAIL: exported GameSmith.pck is missing AGY " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "workspace-tools.mjs", "workspace-paths.mjs", "host-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/kimi/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Kimi " + module)
            quit(1)
            return
    # Kiro support implementations are copied from the shared sources checked above.
    for module in ["worker.mjs", "server.mjs", "protocol.mjs", "mcp.mjs", "workspace-tools.mjs", "process-tree.mjs"]:
        if not FileAccess.file_exists("res://tools/kiro/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Kiro " + module)
            quit(1)
            return
    # Copilot reuses the Kiro MCP and shared support modules checked above.
    for module in ["worker.mjs", "server.mjs", "protocol.mjs"]:
        if not FileAccess.file_exists("res://tools/copilot/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Copilot " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "protocol.mjs"]:
        if not FileAccess.file_exists("res://tools/crush/" + module):
            push_error("FAIL: exported GameSmith.pck is missing Crush " + module)
            quit(1)
            return
    for module in ["worker.mjs", "server.mjs", "policy.mjs"]:
        if not FileAccess.file_exists("res://tools/omp/" + module):
            push_error("FAIL: exported GameSmith.pck is missing OMP " + module)
            quit(1)
            return
    for script in ["omp_agent_controller.gd", "crush_agent_controller.gd", "copilot_agent_controller.gd", "kilo_agent_controller.gd", "kiro_agent_controller.gd", "kimi_agent_controller.gd", "agy_agent_controller.gd", "command_code_agent_controller.gd", "command_code_session.gd", "opencode_agent_controller.gd", "codex_agent_controller.gd", "cline_agent_controller.gd", "cursor_agent_controller.gd", "grok_build_agent_controller.gd"]:
        if not ResourceLoader.exists("res://src/agent/" + script):
            push_error("FAIL: exported GameSmith.pck is missing " + script)
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
