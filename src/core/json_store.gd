class_name JsonStore
extends RefCounted

static func read_dict(path: String, fallback: Dictionary = {}) -> Dictionary:
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)
    var text = FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return fallback.duplicate(true)
    return parsed

static func write_dict(path: String, data: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data, "  "))
    file.close()
    return true

static func append_json_line(path: String, data: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.READ_WRITE)
    if file == null:
        file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.seek_end()
    file.store_line(JSON.stringify(data))
    file.close()
    return true
