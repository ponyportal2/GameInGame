class_name RuntimeLog
extends RefCounted

const MAX_CHARS = 12000
var load_version = 0
var events: Array[Dictionary] = []

func next_version() -> int:
    load_version += 1
    return load_version

func add(kind: String, message: String) -> void:
    var clean = message.strip_edges()
    if clean == "":
        return
    if not events.is_empty() and events[-1].kind == kind and events[-1].message == clean and events[-1].version == load_version:
        events[-1].count = int(events[-1].get("count", 1)) + 1
        return
    events.append({
        "version": load_version,
        "kind": kind,
        "message": clean.left(3000),
        "count": 1,
        "time": Time.get_time_string_from_system()
    })
    while JSON.stringify(events).length() > MAX_CHARS and events.size() > 1:
        events.pop_front()

func read_text() -> String:
    var lines: Array[String] = []
    for event in events:
        var repeat_text = " x%d" % event.count if int(event.count) > 1 else ""
        lines.append("[%s][load %d][%s]%s %s" % [event.time, event.version, event.kind, repeat_text, event.message])
    var engine_tail = _engine_log_tail()
    if engine_tail != "":
        lines.append("\n--- Godot log tail ---\n" + engine_tail)
    return "\n".join(lines).right(MAX_CHARS)

func _engine_log_tail() -> String:
    var path = "user://logs/gamesmith.log"
    if not FileAccess.file_exists(path):
        return ""
    return FileAccess.get_file_as_string(path).right(6000)
