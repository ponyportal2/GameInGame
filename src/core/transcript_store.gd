class_name TranscriptStore
extends RefCounted

var metadata = MetadataStore.new()

func append(game_name: String, role: String, content: String) -> void:
    JsonStore.append_json_line(metadata.transcript_path(game_name), {
        "time": Time.get_datetime_string_from_system(true),
        "role": role,
        "content": content
    })

func read_all(game_name: String, max_entries: int = 200) -> Array[Dictionary]:
    var path = metadata.transcript_path(game_name)
    var out: Array[Dictionary] = []
    if not FileAccess.file_exists(path): return out
    var f = FileAccess.open(path, FileAccess.READ)
    while f != null and not f.eof_reached():
        var line = f.get_line().strip_edges()
        if line == "": continue
        var parsed = JSON.parse_string(line)
        if typeof(parsed) == TYPE_DICTIONARY:
            out.append(parsed)
    if out.size() > max_entries:
        return out.slice(out.size() - max_entries)
    return out
