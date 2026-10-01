class_name LegacyDataMigrator
extends RefCounted

const LEGACY_APP_DIR_NAME = "GameSmith Host"
const CURRENT_APP_DIR_NAME = "GameSmithHost"

static func migrate_user_data() -> Dictionary:
    var new_root = ProjectSettings.globalize_path("user://").trim_suffix("/").trim_suffix("\\")
    var old_root = new_root.get_base_dir().path_join(LEGACY_APP_DIR_NAME)
    if old_root == new_root or not DirAccess.dir_exists_absolute(old_root):
        return {"ok": true, "copied": 0, "skipped": 0, "source_found": false}
    var result = migrate_absolute(old_root, new_root)
    result["source_found"] = true
    return result

static func migrate_absolute(old_root: String, new_root: String) -> Dictionary:
    if not DirAccess.dir_exists_absolute(old_root):
        return {"ok": true, "copied": 0, "skipped": 0, "source_found": false}
    var counts = {"copied": 0, "skipped": 0}
    var err = DirAccess.make_dir_recursive_absolute(new_root)
    if err != OK and err != ERR_ALREADY_EXISTS:
        return {"ok": false, "error": "Could not create new app-data root.", "copied": 0, "skipped": 0}
    var ok = _copy_missing_tree(old_root, new_root, counts)
    return {"ok": ok, "copied": counts.copied, "skipped": counts.skipped, "source_found": true, "error": "" if ok else "Could not copy one or more legacy app-data files."}

static func remove_tree_absolute(abs_path: String) -> bool:
    if not DirAccess.dir_exists_absolute(abs_path):
        return true
    var dir = DirAccess.open(abs_path)
    if dir == null:
        return false
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var child = abs_path.path_join(item)
        if dir.current_is_dir():
            if not remove_tree_absolute(child):
                dir.list_dir_end()
                return false
        else:
            if DirAccess.remove_absolute(child) != OK:
                dir.list_dir_end()
                return false
        item = dir.get_next()
    dir.list_dir_end()
    return DirAccess.remove_absolute(abs_path) == OK

static func _copy_missing_tree(src_abs: String, dst_abs: String, counts: Dictionary) -> bool:
    var dir = DirAccess.open(src_abs)
    if dir == null:
        return false
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var src = src_abs.path_join(item)
        var dst = dst_abs.path_join(item)
        if dir.current_is_dir():
            var err = DirAccess.make_dir_recursive_absolute(dst)
            if err != OK and err != ERR_ALREADY_EXISTS:
                dir.list_dir_end()
                return false
            if not _copy_missing_tree(src, dst, counts):
                dir.list_dir_end()
                return false
        else:
            if FileAccess.file_exists(dst):
                counts.skipped = int(counts.skipped) + 1
            else:
                var copy_err = DirAccess.copy_absolute(src, dst)
                if copy_err != OK:
                    dir.list_dir_end()
                    return false
                counts.copied = int(counts.copied) + 1
        item = dir.get_next()
    dir.list_dir_end()
    return true
