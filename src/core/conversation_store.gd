class_name ConversationStore
extends RefCounted

const VERIFICATION_PREFIX = "GameSmith verification rejected that completion:"

var metadata = MetadataStore.new()

func exists(game_name: String) -> bool:
    return FileAccess.file_exists(metadata.conversation_path(game_name))

func append(game_name: String, message: Dictionary) -> bool:
    return JsonStore.append_json_line(metadata.conversation_path(game_name), message)

func read_all(game_name: String) -> Array:
    var path = metadata.conversation_path(game_name)
    var out: Array = []
    if not FileAccess.file_exists(path):
        return out
    var file = FileAccess.open(path, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line = file.get_line().strip_edges()
        if line == "":
            continue
        var parsed = JSON.parse_string(line)
        if typeof(parsed) == TYPE_DICTIONARY:
            out.append(parsed)
    return out

func read_for_provider(game_name: String) -> Array:
    var raw = read_all(game_name)
    var out: Array = []
    for message in raw:
        if _is_verification_message(message):
            if not out.is_empty():
                var previous = out[-1]
                if typeof(previous) == TYPE_DICTIONARY and str(previous.get("role", "")) == "assistant" and not previous.has("tool_calls"):
                    out.pop_back()
            continue
        out.append(message)
    return out

func needs_recovery_marker(history: Array) -> bool:
    if history.is_empty():
        return false
    var last = history[-1]
    if typeof(last) != TYPE_DICTIONARY:
        return true
    if str(last.get("role", "")) != "assistant":
        return true
    if last.has("tool_calls") and not Array(last.get("tool_calls", [])).is_empty():
        return true
    return str(last.get("content", "")).strip_edges() == ""

func recovery_marker() -> Dictionary:
    return {
        "role": "assistant",
        "content": "The previous GameSmith turn ended before a final response. The workspace and Git may contain partial work; inspect the current files before acting on the new request."
    }

func import_legacy_transcript(game_name: String, entries: Array) -> Array:
    if exists(game_name):
        return read_for_provider(game_name)
    var imported: Array = []
    for entry in entries:
        if typeof(entry) != TYPE_DICTIONARY:
            continue
        var role = str(entry.get("role", ""))
        if role != "user" and role != "assistant":
            continue
        imported.append({"role": role, "content": str(entry.get("content", ""))})
    if imported.is_empty():
        return imported
    var path = metadata.conversation_path(game_name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return []
    for message in imported:
        file.store_line(JSON.stringify(message))
    file.close()
    return imported

func _is_verification_message(message: Dictionary) -> bool:
    return str(message.get("role", "")) == "system" and str(message.get("content", "")).begins_with(VERIFICATION_PREFIX)
