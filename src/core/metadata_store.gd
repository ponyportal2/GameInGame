class_name MetadataStore
extends RefCounted

const HOST_ROOT = "user://host"
const META_ROOT = HOST_ROOT + "/games"
const SETTINGS_PATH = HOST_ROOT + "/settings.json"
const CREDENTIALS_PATH = HOST_ROOT + "/credentials.json"

func ensure() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(META_ROOT))

func create_game(name: String) -> bool:
    ensure()
    var dir = game_meta_dir(name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    return JsonStore.write_dict(dir.path_join("metadata.json"), {
        "name": name,
        "provider_override": "",
        "model_override": "",
        "last_working_commit": "",
        "created_at": Time.get_datetime_string_from_system(true)
    })

func delete_game(name: String) -> bool:
    return _remove_tree(game_meta_dir(name))

func rename_game(old_name: String, new_name: String, new_workspace: String = "") -> bool:
    var old_dir = game_meta_dir(old_name)
    var new_dir = game_meta_dir(new_name)
    var moved = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(old_dir))
    if moved:
        var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(old_dir), ProjectSettings.globalize_path(new_dir))
        if err != OK:
            return false
    var meta = read_game(new_name)
    meta.name = new_name
    var originals: Dictionary = {}
    var rebound = true
    if new_workspace != "":
        # Pi resolves --session against the cwd recorded in its session header.
        # Rebind that header only; retain every conversation entry byte-for-byte.
        var sessions = new_dir.path_join("pi/sessions")
        var dir = DirAccess.open(sessions)
        if dir != null:
            for file_name in dir.get_files():
                if not file_name.ends_with(".jsonl"):
                    continue
                var path = sessions.path_join(file_name)
                var bytes = FileAccess.get_file_as_bytes(path)
                var newline = bytes.find(10)
                if newline < 0:
                    continue
                var header = JSON.parse_string(bytes.slice(0, newline).get_string_from_utf8())
                if typeof(header) != TYPE_DICTIONARY or str(header.get("type", "")) != "session":
                    continue
                header["cwd"] = ProjectSettings.globalize_path(new_workspace)
                var replacement = (JSON.stringify(header) + "\n").to_utf8_buffer()
                replacement.append_array(bytes.slice(newline + 1))
                if not JsonStore.write_bytes_atomic(path, replacement):
                    rebound = false
                    break
                originals[path] = bytes
    if rebound and write_game(new_name, meta):
        return true
    for path in originals:
        JsonStore.write_bytes_atomic(path, originals[path])
    if moved:
        DirAccess.rename_absolute(ProjectSettings.globalize_path(new_dir), ProjectSettings.globalize_path(old_dir))
    return false

func read_game(name: String) -> Dictionary:
    return JsonStore.read_dict(game_meta_dir(name).path_join("metadata.json"), {"name": name})

func write_game(name: String, data: Dictionary) -> bool:
    return JsonStore.write_dict(game_meta_dir(name).path_join("metadata.json"), data)

func transcript_path(name: String) -> String:
    return game_meta_dir(name).path_join("transcript.jsonl")

func game_meta_dir(name: String) -> String:
    return META_ROOT.path_join(name)

func snapshot_dir(name: String) -> String:
    return game_meta_dir(name).path_join("working_snapshot")

func global_settings() -> Dictionary:
    return JsonStore.read_dict(SETTINGS_PATH, {
        "provider": "openrouter",
        "model": "openai/gpt-5.6",
        "custom_base_url": "",
        "reasoning_effort": "",
        "max_agent_steps": 150,
        "llm_call_delay_sec": 6.0,
        "compaction_auto_tokens": 100000,
        "compaction_keep_recent_tokens": 20000,
        "allow_rendered_tests": false,
    })

func save_global_settings(data: Dictionary) -> bool:
    return JsonStore.write_dict(SETTINGS_PATH, data)

func credentials() -> Dictionary:
    return JsonStore.read_dict(CREDENTIALS_PATH, {})

func save_credentials(data: Dictionary) -> bool:
    return JsonStore.write_dict(CREDENTIALS_PATH, data)

func _remove_tree(path: String) -> bool:
    var abs = ProjectSettings.globalize_path(path)
    if not DirAccess.dir_exists_absolute(abs):
        return true
    return _remove_tree_abs(abs) == OK

func _remove_tree_abs(abs: String) -> Error:
    var dir = DirAccess.open(abs)
    if dir == null:
        return ERR_CANT_OPEN
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var child = abs.path_join(item)
        if dir.current_is_dir():
            var err = _remove_tree_abs(child)
            if err != OK:
                return err
        else:
            var err_file = DirAccess.remove_absolute(child)
            # Git object files can be read-only on Windows. Clear that attribute
            # only after deletion fails, within the explicitly deleted tree.
            if err_file != OK and OS.get_name() == "Windows":
                if FileAccess.set_read_only_attribute(child, false) == OK:
                    err_file = DirAccess.remove_absolute(child)
            if err_file != OK:
                return err_file
        item = dir.get_next()
    dir.list_dir_end()
    return DirAccess.remove_absolute(abs)
