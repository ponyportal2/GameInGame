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

func rename_game(old_name: String, new_name: String) -> bool:
    var old_dir = game_meta_dir(old_name)
    var new_dir = game_meta_dir(new_name)
    if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(old_dir)):
        var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(old_dir), ProjectSettings.globalize_path(new_dir))
        if err != OK:
            return false
    var meta = read_game(new_name)
    meta.name = new_name
    return write_game(new_name, meta)

func read_game(name: String) -> Dictionary:
    return JsonStore.read_dict(game_meta_dir(name).path_join("metadata.json"), {"name": name})

func write_game(name: String, data: Dictionary) -> bool:
    return JsonStore.write_dict(game_meta_dir(name).path_join("metadata.json"), data)

func transcript_path(name: String) -> String:
    return game_meta_dir(name).path_join("transcript.jsonl")

func conversation_path(name: String) -> String:
    return game_meta_dir(name).path_join("conversation.jsonl")

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
            if err_file != OK:
                return err_file
        item = dir.get_next()
    dir.list_dir_end()
    return DirAccess.remove_absolute(abs)
