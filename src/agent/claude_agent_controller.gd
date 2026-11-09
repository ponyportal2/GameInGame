extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "Claude Code"

func _native_directory_name() -> String:
    return "claude"

func _uses_reload_grants() -> bool:
    return false

func _retire_after_cancel() -> bool:
    # A stopped backend cannot issue tools during the next operation.
    return true

func _native_prompt() -> String:
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith MCP read/edit/write/search/list").replace("Pi's", "Claude Code's").replace("Pi process", "Claude Code process")
    prompt += "\nUse only tools supplied by the gamesmith MCP server; do not use native or external tools. The native working directory is private host metadata; GameSmith MCP paths are relative to the game workspace. Use read with 1-based offset/limit, edit with path/old_text/new_text and write with path/content. Model, authentication, reasoning and compaction are managed by Claude Code.\n"
    return prompt
