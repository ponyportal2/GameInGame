extends SceneTree

const Inventory = preload("res://src/agent/harness_inventory.gd")
const Config = preload("res://src/pi/pi_runtime_config.gd")
const Metadata = preload("res://src/core/metadata_store.gd")
const NATIVE_TOOLS = {
    "command-code": "read_file/edit_file/write_file/grep/glob/read_directory",
    "opencode": "native MCP with the gamesmith_ prefix",
    "kilo": "native MCP with the gamesmith_ prefix",
    "codex": "native dynamic tools named gamesmith_<command>",
    "cline": "gamesmith__read",
    "cursor": "tools supplied by the gamesmith MCP server",
    "grok-build": "tool_name=gamesmith__<command>",
    "agy": "call_mcp_tool with ServerName=gamesmith",
    "kimi": "tools supplied by the gamesmith MCP server",
    "kiro": "tools supplied by the gamesmith MCP server",
    "copilot": "named gamesmith-<tool>",
    "crush": "named mcp_gamesmith_<tool>",
    "omp": "gamesmith_<command> host tools",
}
var passed := 0
var failed := 0

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS: " + label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var metadata = Metadata.new()
    var entries = Inventory.all()
    check(entries.size() == 14, "prompt contracts cover every catalog harness")
    for entry in entries:
        var controller = load("res://" + str(entry.controller)).new()
        controller.game_name = "Prompt contract " + str(entry.id)
        for blender_enabled in [false, true]:
            check(metadata.write_game(controller.game_name, {"blender_enabled": blender_enabled}), "isolated metadata " + str(entry.id))
            var prompt: String
            if entry.id == "pi":
                # Exercise the file actually supplied to Pi, including assembly.
                var result = Config.prepare(controller.game_name, "user://prompt-workspace", {"provider": "openrouter", "model": "fixture"}, {"openrouter": "fixture-key"}, metadata.read_game(controller.game_name))
                check(result.get("ok", false), "Pi production preparation")
                prompt = FileAccess.get_file_as_string(result.get("prompt_path", "")) if result.get("ok", false) else ""
            else:
                # This is the same virtual method production startup writes to prompt.md.
                prompt = controller._native_prompt()
            var label = str(entry.id) + " blender=" + str(blender_enabled)
            for clause in ["Stay inside it", "main.gd", "Use preload() for helper scripts", "Script inheritance", "literal PNG/JPG/JPEG/WAV/OGG", "outside the static check", "res:// refers to the GameSmith host project", "Image.load_from_file(assets.path(", "ImageTexture.create_from_image(image)", "Only one image job can run at a time", "inspect_runtime", "set_properties", "parameter patch", "Never infer", "live-only", "do not reload even when inspection fails", "immediate property readback separately from visual verification and persistence", "Godot late-child lifecycle", "request_ready()", "process_physics_priority", "ordinary startup alone", "completed process and physics ticks", "rg_search", "output_truncated"]:
                check(clause in prompt, label + " retains " + clause)
            check(("- Blender is available" in prompt) == blender_enabled, label + " Blender tool instruction toggles")
            check(("or generated with Blender" in prompt) == blender_enabled, label + " Blender asset advice toggles")
            if entry.id == "pi":
                check("Pi's read/edit/write/grep/find/ls" in prompt, label + " Pi tool terminology")
            else:
                check(not "Pi's" in prompt and not "Pi process" in prompt, label + " no stale Pi terminology")
                check(str(entry.label) in prompt, label + " native harness terminology")
                check(NATIVE_TOOLS.get(entry.id, "MISSING CONTRACT") in prompt, label + " native tool instruction")
        controller.free()
    print("Prompt contracts: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)
