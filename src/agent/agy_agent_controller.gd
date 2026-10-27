extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "AGY"

func _retire_after_cancel() -> bool:
    # Stream-JSON has no cancellation record; Stop kills the native tree.
    return true

func _uses_reload_grants() -> bool:
    # AGY MCP calls wait directly for the ordinary host reload approval.
    return false


func _native_prompt() -> String:
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith MCP read/edit/write/search/list").replace("Pi's", "AGY's").replace("Pi process", "AGY process")
    prompt += "\nUse only GameSmith MCP tools through call_mcp_tool with ServerName=gamesmith, ToolName=<command>, and Arguments containing its arguments. Commands include read, edit, write, search, list, start_test_game, read_test_log, stop_test_game, inspect_runtime, set_properties, reload_game and Git tools. GameSmith file paths are relative to the actual game workspace (for example main.gd); the native working directory is private host metadata. Use read with 1-based offset/limit, edit with path/old_text/new_text and write with path/content. Native filesystem, shell, browser, delegation and external MCP tools are denied by the GameSmith hook. AGY owns model, reasoning and compaction.\n"
    prompt += "For headless testing, read_test_log state=running with load_result.ok=true means startup succeeded; latest_outcome=accepted also confirms acceptance. The test keeps running until stop_test_game: do not wait for it to exit or repeatedly poll identical logs. After checks pass, stop the run using its run_id, then use reload_game if a full reload is needed. A successful live parameter patch with set_properties needs no reload. Failed tests or reloads require repair and retesting before finishing.\n"
    return prompt
