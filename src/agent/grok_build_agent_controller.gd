extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "Grok Build"

func _retire_after_cancel() -> bool:
    # Retire pending MCP work on Stop; the next message resumes native history.
    return true

func _native_directory_name() -> String:
    return "grok-build"


func _native_prompt() -> String:
    var prompt = GamePromptScript.build(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith MCP read/edit/write/search/list").replace("Pi's", "Grok Build's").replace("Pi process", "Grok Build process")
    prompt += "\nDiscover GameSmith MCP tools with search_tool, then use_tool with tool_name=gamesmith__<command> and tool_input containing its arguments. Use only tools supplied by the gamesmith MCP server: read, edit, write, search, list, start_test_game, read_test_log, stop_test_game, inspect_runtime, set_properties, reload_game and Git commands. Native shell, file access and external MCP tools are denied. Your native working directory is private host metadata; GameSmith MCP file paths are relative to the actual game workspace, for example main.gd. Use read with 1-based offset/limit, edit with path/old_text/new_text and write with path/content. Model, reasoning and compaction are managed by Grok Build.\n"
    prompt += "For headless testing, read_test_log state=running with load_result.ok=true means startup succeeded; latest_outcome=accepted also confirms acceptance. The test keeps running until stop_test_game: do not wait for it to exit or repeatedly poll identical logs. After checks pass, stop the run using its run_id, then use reload_game if a full reload is needed. A successful live parameter patch with set_properties needs no reload.\n"
    return prompt
