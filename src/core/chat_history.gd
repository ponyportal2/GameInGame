extends RefCounted
## UI history only. Native conversation import continues to use transcript.jsonl.
var metadata = MetadataStore.new()

func path(game: String) -> String:
    return metadata.game_meta_dir(game).path_join("chat.jsonl")

func exists(game: String) -> bool:
    return FileAccess.file_exists(path(game))

func seed(game: String, entries: Array) -> bool:
    var lines = PackedStringArray([JSON.stringify({"type": "init"})])
    for entry in entries:
        lines.append(JSON.stringify({"type": "message", "role": entry.get("role", "system"), "content": entry.get("content", "")}))
    var saved = JsonStore.write_bytes_atomic(path(game), ("\n".join(lines) + "\n").to_utf8_buffer())
    if not saved: push_warning("Could not initialize visible chat history.")
    return saved

func append(game: String, event: Dictionary) -> void:
    if game == "": return
    var filename = path(game)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(filename.get_base_dir()))
    var file = FileAccess.open(filename, FileAccess.READ_WRITE)
    if file == null: file = FileAccess.open(filename, FileAccess.WRITE)
    if file == null:
        push_warning("Could not save visible chat history.")
        return
    # A process killed during an append may leave an incomplete final record.
    if file.get_length() > 0:
        file.seek(file.get_length() - 1)
        if file.get_8() != 10:
            file.seek_end()
            file.store_8(10)
    file.seek_end()
    file.store_line(JSON.stringify(event))
    file.close()

func read_all(game: String) -> Array[Dictionary]:
    var events: Array[Dictionary] = []
    var file = FileAccess.open(path(game), FileAccess.READ)
    if file == null: return events
    while not file.eof_reached():
        var line = file.get_line()
        if line.strip_edges() == "": continue
        var value = JSON.parse_string(line)
        if not value is Dictionary: continue
        if value.get("type") == "reconcile":
            _reconcile(events, str(value.get("content", "")), str(value.get("mode", "latest_stream")))
        elif value.get("type") in ["message", "delta", "end"]:
            events.append(value)
    return events

func _reconcile(events: Array[Dictionary], replacement: String, mode: String = "latest_stream") -> void:
    if mode == "whole_turn":
        var start = 0
        for i in range(events.size() - 1, -1, -1):
            if events[i].get("type") == "message" and events[i].get("role") == "user":
                start = i + 1
                break
        var insertion = start
        var found = false
        for i in range(events.size() - 1, start - 1, -1):
            if events[i].get("role") == "assistant" and events[i].get("type") in ["message", "delta", "end"]:
                insertion = i
                found = true
                events.remove_at(i)
        if replacement != "":
            events.insert(insertion if found else start, {"type": "message", "role": "assistant", "content": replacement})
        return
    # Replace only the latest assistant stream in this request. Earlier thinking,
    # tools and commentary remain visible when a native result is corrected.
    for i in range(events.size() - 1, -1, -1):
        var event = events[i]
        if event.get("role") == "user": break
        if event.get("type") != "delta" or event.get("role") != "assistant": continue
        var first = i
        while first > 0 and events[first - 1].get("type") == "delta" and events[first - 1].get("role") == "assistant":
            first -= 1
        var last = i + 1
        if last < events.size() and events[last].get("type") == "end" and events[last].get("role") == "assistant":
            last += 1
        for index in range(last - 1, first - 1, -1): events.remove_at(index)
        if replacement != "":
            events.insert(first, {"type": "message", "role": "assistant", "content": replacement})
        return
    if replacement != "":
        events.append({"type": "message", "role": "assistant", "content": replacement})
