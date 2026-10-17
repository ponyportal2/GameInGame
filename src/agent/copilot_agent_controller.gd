extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "Copilot"

func _uses_reload_grants() -> bool:
    return false

func _retire_after_cancel() -> bool:
    # Retire the cancelled MCP queue before resuming the native conversation.
    # Resume the same native conversation in a fresh backend after Stop.
    return true


func _native_prompt() -> String:
    var prompt = PiRuntimeConfigScript._game_prompt(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith MCP read/edit/write/search/list").replace("Pi's", "Copilot's").replace("Pi process", "Copilot process")
    prompt += "\nUse only tools supplied by the gamesmith MCP server, named gamesmith-<tool>: read, edit, write, search, list, start_test_game, read_test_log, stop_test_game, inspect_runtime, set_properties, reload_game and Git commands. Native shell, file access and external MCP tools are denied. Your native working directory is private host metadata; GameSmith MCP file paths are relative to the actual game workspace, for example main.gd. Use read with 1-based offset/limit, edit with path/old_text/new_text and write with path/content. Model, reasoning and compaction are managed by Copilot.\n"
    prompt += "For headless testing, read_test_log state=running with load_result.ok=true means startup succeeded; latest_outcome=accepted also confirms acceptance. The test keeps running until stop_test_game: do not wait for it to exit or repeatedly poll identical logs. After checks pass, stop the run using its run_id, then use reload_game if a full reload is needed. A successful live parameter patch with set_properties needs no reload.\n"
    return prompt
