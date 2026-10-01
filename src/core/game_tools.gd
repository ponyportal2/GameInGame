class_name GameTools
extends RefCounted

var workspace = ""
var git = GitService.new()
var runner: GameRunner

func _init(p_workspace: String = "", p_runner: GameRunner = null):
    workspace = p_workspace
    runner = p_runner

func list_files(relative_dir: String = "") -> Dictionary:
    var base = workspace
    if relative_dir != "":
        base = _path(relative_dir)
        if base == "": return _unsafe()
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):
        return {"ok": false, "error": "Directory not found."}
    var result: Array[String] = []
    _walk(base, workspace, result)
    return {"ok": true, "files": result}

func read_file(relative_path: String) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found."}
    return {"ok": true, "content": FileAccess.get_file_as_string(path).left(30000)}

func search_text(query: String) -> Dictionary:
    if query == "": return {"ok": false, "error": "Query is empty."}
    var listing = list_files()
    if not listing.ok: return listing
    var matches: Array[String] = []
    for rel in listing.files:
        if rel.begins_with(".git/") or not rel.get_extension().to_lower() in ["gd", "txt", "md", "json", "cfg"]:
            continue
        var content = FileAccess.get_file_as_string(_path(rel))
        var lines = content.split("\n")
        for i in lines.size():
            if query.to_lower() in lines[i].to_lower():
                matches.append("%s:%d: %s" % [rel, i + 1, lines[i].strip_edges()])
                if matches.size() >= 100:
                    return {"ok": true, "matches": matches}
    return {"ok": true, "matches": matches}

func write_file(relative_path: String, content: String) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f == null: return {"ok": false, "error": "Could not write file."}
    f.store_string(content)
    f.close()
    return {"ok": true, "bytes": content.to_utf8_buffer().size()}

func patch_file(relative_path: String, old_text: String, new_text: String) -> Dictionary:
    var read = read_file(relative_path)
    if not read.ok: return read
    if old_text == "": return {"ok": false, "error": "old_text cannot be empty."}
    var count = read.content.count(old_text)
    if count != 1:
        return {"ok": false, "error": "Patch requires exactly one match; found %d." % count}
    return write_file(relative_path, read.content.replace(old_text, new_text))

func move_path(from_relative: String, to_relative: String) -> Dictionary:
    var from = _path(from_relative)
    var to = _path(to_relative)
    if from == "" or to == "": return _unsafe()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))
    var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
    return {"ok": err == OK, "error": "" if err == OK else "Move failed (%d)." % err}

func delete_path(relative_path: String) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    if path == workspace: return _unsafe()
    var abs = ProjectSettings.globalize_path(path)
    if DirAccess.dir_exists_absolute(abs):
        return {"ok": _remove_tree_abs(abs) == OK}
    if FileAccess.file_exists(path):
        var err = DirAccess.remove_absolute(abs)
        return {"ok": err == OK, "error": "" if err == OK else "Delete failed (%d)." % err}
    return {"ok": false, "error": "Path not found."}

func git_status() -> Dictionary: return git.status(workspace)
func git_diff() -> Dictionary: return git.diff(workspace)
func git_log(limit: int = 12) -> Dictionary: return git.log(workspace, limit)
func git_commit(message: String) -> Dictionary: return git.commit(workspace, message)

func reload_game() -> Dictionary:
    if runner == null: return {"ok": false, "error": "Runner unavailable."}
    return runner.load_game(workspace)

func read_runtime_log() -> Dictionary:
    if runner == null: return {"ok": false, "error": "Runner unavailable."}
    return {"ok": true, "log": runner.runtime_log.read_text()}

func execute(name: String, args: Dictionary) -> Dictionary:
    match name:
        "list_files": return list_files(str(args.get("path", "")))
        "read_file": return read_file(str(args.get("path", "")))
        "search_text": return search_text(str(args.get("query", "")))
        "write_file": return write_file(str(args.get("path", "")), str(args.get("content", "")))
        "patch_file": return patch_file(str(args.get("path", "")), str(args.get("old_text", "")), str(args.get("new_text", "")))
        "move_path": return move_path(str(args.get("from", "")), str(args.get("to", "")))
        "delete_path": return delete_path(str(args.get("path", "")))
        "git_status": return git_status()
        "git_diff": return git_diff()
        "git_log": return git_log(int(args.get("limit", 12)))
        "git_commit": return git_commit(str(args.get("message", "Update generated game")))
        "reload_game": return reload_game()
        "read_runtime_log": return read_runtime_log()
        _: return {"ok": false, "error": "Unknown tool: " + name}

func _path(relative_path: String) -> String:
    return PathUtils.join_workspace(workspace, relative_path)

func _unsafe() -> Dictionary:
    return {"ok": false, "error": "Unsafe path. Tools are limited to the current game workspace."}

func _walk(dir_path: String, root_path: String, out: Array[String]) -> void:
    var dir = DirAccess.open(dir_path)
    if dir == null: return
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var full = dir_path.path_join(item)
        var rel = full.trim_prefix(root_path + "/")
        if dir.current_is_dir():
            if item == ".git":
                item = dir.get_next(); continue
            _walk(full, root_path, out)
        else:
            out.append(rel)
        item = dir.get_next()
    dir.list_dir_end()

func _remove_tree_abs(abs: String) -> Error:
    var dir = DirAccess.open(abs)
    if dir == null: return ERR_CANT_OPEN
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var child = abs.path_join(item)
        if dir.current_is_dir():
            var err = _remove_tree_abs(child)
            if err != OK: return err
        else:
            var err_file = DirAccess.remove_absolute(child)
            if err_file != OK: return err_file
        item = dir.get_next()
    dir.list_dir_end()
    return DirAccess.remove_absolute(abs)
