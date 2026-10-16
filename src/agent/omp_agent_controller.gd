extends "res://src/agent/cline_agent_controller.gd"

func _harness_name() -> String:
    return "OMP"

func _uses_reload_grants() -> bool:
    return false

func _retire_after_cancel() -> bool:
    return true


func _native_prompt() -> String:
    var prompt = PiRuntimeConfigScript._game_prompt(_blender_enabled()).replace("Pi's read/edit/write/grep/find/ls", "GameSmith host read/edit/write/search/list").replace("Pi's", "OMP's").replace("Pi process", "OMP process")
    prompt += "\nUse only gamesmith_read, gamesmith_write, gamesmith_edit, gamesmith_search, gamesmith_list and gamesmith_<command> host tools. File paths are relative to the actual game workspace, e.g. main.gd. Your native cwd is private metadata. Model, provider, reasoning and compaction belong to OMP. Headless read_test_log state=running with load_result.ok=true confirms successful startup; stop that run rather than waiting for it to exit by itself, then request reload.\n"
    return prompt
