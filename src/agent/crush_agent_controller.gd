extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "Crush"

func _uses_reload_grants() -> bool:
    return false

func _retire_after_cancel() -> bool:
    return true


func _native_prompt() -> String:
    var prompt = PiRuntimeConfigScript._game_prompt(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith MCP read/edit/write/search/list").replace("Pi's", "Crush's").replace("Pi process", "Crush process")
    prompt += "\nUse only tools supplied by the gamesmith MCP server, named mcp_gamesmith_<tool>: read, edit, write, search, list, start_test_game, read_test_log, stop_test_game, reload_game and Git commands. Native shell, file access, delegation and external MCP tools are disabled. Your native working directory is private host metadata; GameSmith MCP file paths are relative to the actual game workspace, for example main.gd. Use read with 1-based offset/limit, edit with path/old_text/new_text and write with path/content. Model, reasoning and compaction are managed by Crush.\n"
    prompt += "For headless testing, read_test_log state=running with load_result.ok=true means startup succeeded; latest_outcome=accepted also confirms acceptance. The test keeps running until stop_test_game: do not wait for it to exit or repeatedly poll identical logs. After checks pass, stop the run using its run_id, then reload_game before handing the game to the player.\n"
    return prompt
