extends "res://src/agent/opencode_agent_controller.gd"

func _harness_name() -> String:
    return "Kilo"

func _harness_id() -> String:
    return "kilo"

func _on_command_record(record: Dictionary) -> void:
    if record.get("initialization_failed", false):
        restart_after_finish = true
    super._on_command_record(record)

func _fail(message: String) -> void:
    last_error = message
    super._fail(message)

func start_new_session() -> Dictionary:
    if busy: return {"ok": false, "error": "Stop Kilo before starting a new session."}
    if not acquire_editor(): return {"ok": false, "error": last_error}
    var directory = ProjectSettings.globalize_path(metadata.game_meta_dir(game_name).path_join("kilo"))
    var session_file = directory.path_join("session.json")
    var archive = ""
    if FileAccess.file_exists(session_file):
        archive = directory.path_join("session.previous-%d-%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
        if DirAccess.rename_absolute(session_file, archive) != OK:
            return {"ok": false, "error": "Could not preserve the previous Kilo session reference. No session was reset."}
    restart_runtime()
    return {"ok": true, "archive": archive}
