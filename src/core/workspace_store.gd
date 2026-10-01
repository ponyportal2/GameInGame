class_name WorkspaceStore
extends RefCounted

const GAMES_ROOT = "user://games"
var git = GitService.new()
var metadata = MetadataStore.new()

func ensure() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GAMES_ROOT))
    metadata.ensure()

func list_games() -> Array[String]:
    ensure()
    var names: Array[String] = []
    var dir = DirAccess.open(GAMES_ROOT)
    if dir == null:
        return names
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        if dir.current_is_dir() and not item.begins_with("."):
            names.append(item)
        item = dir.get_next()
    dir.list_dir_end()
    names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
    return names

func create_game(raw_name: String) -> Dictionary:
    ensure()
    var base = PathUtils.sanitize_game_name(raw_name)
    var name = base
    var n = 2
    while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(game_path(name))):
        name = "%s %d" % [base, n]
        n += 1
    var path = game_path(name)
    var err = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
    if err != OK:
        return {"ok": false, "error": "Could not create workspace."}
    var git_result = git.init_repo(path)
    if not git_result.get("ok", false):
        _remove_tree(path)
        return {"ok": false, "error": "Git init failed: " + str(git_result.get("output", "unknown error"))}
    if not metadata.create_game(name):
        _remove_tree(path)
        return {"ok": false, "error": "Could not create host metadata."}
    return {"ok": true, "name": name, "path": path}

func rename_game(old_name: String, raw_new_name: String) -> Dictionary:
    var new_name = PathUtils.sanitize_game_name(raw_new_name)
    if old_name == new_name:
        return {"ok": true, "name": old_name}
    if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(game_path(new_name))):
        return {"ok": false, "error": "A game with that name already exists."}
    var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(game_path(old_name)), ProjectSettings.globalize_path(game_path(new_name)))
    if err != OK:
        return {"ok": false, "error": "Could not rename workspace."}
    if not metadata.rename_game(old_name, new_name):
        DirAccess.rename_absolute(ProjectSettings.globalize_path(game_path(new_name)), ProjectSettings.globalize_path(game_path(old_name)))
        return {"ok": false, "error": "Could not migrate host metadata."}
    return {"ok": true, "name": new_name}

func delete_game(name: String) -> bool:
    var ok = _remove_tree(game_path(name))
    return metadata.delete_game(name) and ok

func game_path(name: String) -> String:
    return GAMES_ROOT.path_join(name)

func save_working_snapshot(name: String) -> bool:
    var dest = metadata.snapshot_dir(name)
    _remove_tree(dest)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
    var ok = _copy_tree(game_path(name), dest, true)
    if ok:
        var meta = metadata.read_game(name)
        meta.last_working_commit = git.head(game_path(name))
        meta.last_loaded_at = Time.get_datetime_string_from_system(true)
        metadata.write_game(name, meta)
    return ok

func has_working_snapshot(name: String) -> bool:
    return FileAccess.file_exists(metadata.snapshot_dir(name).path_join("main.gd"))

func _copy_tree(src: String, dst: String, skip_git: bool = false) -> bool:
    var src_abs = ProjectSettings.globalize_path(src)
    var dir = DirAccess.open(src_abs)
    if dir == null:
        return false
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        if skip_git and item == ".git":
            item = dir.get_next()
            continue
        var from = src.path_join(item)
        var to = dst.path_join(item)
        if dir.current_is_dir():
            DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
            if not _copy_tree(from, to, false):
                return false
        else:
            var from_abs = ProjectSettings.globalize_path(from)
            var to_abs = ProjectSettings.globalize_path(to)
            var err = DirAccess.copy_absolute(from_abs, to_abs)
            if err != OK:
                return false
        item = dir.get_next()
    dir.list_dir_end()
    return true

func _remove_tree(path: String) -> bool:
    var abs = ProjectSettings.globalize_path(path)
    if not DirAccess.dir_exists_absolute(abs):
        return true
    return metadata._remove_tree_abs(abs) == OK
