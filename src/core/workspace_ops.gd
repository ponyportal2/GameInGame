class_name WorkspaceOps
extends RefCounted

# Every agent file tool runs through this boundary. Keeping containment, link and
# .git rules here means the tool facade cannot grow a second, weaker path check.

const DEFAULT_READ_LINES = 300
const MAX_READ_LINES = 1000

var workspace = ""

func _init(p_workspace: String = ""):
    workspace = p_workspace

func list_files(relative_dir: String = "") -> Dictionary:
    var base = workspace
    if relative_dir != "":
        base = _path(relative_dir)
        if base == "": return _unsafe()
        if _linked(relative_dir): return _linked_path()
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):
        return {"ok": false, "error": "Directory not found."}
    var result: Array[String] = []
    _walk(base, workspace, result)
    return {"ok": true, "files": result}

func read_file(relative_path: String, offset: int = 1, limit: int = DEFAULT_READ_LINES) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    if _linked(relative_path): return _linked_path()
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found."}
    var full = FileAccess.get_file_as_string(path)
    var lines = full.split("\n", true)
    var start_line = maxi(1, offset)
    var bounded_limit = clampi(limit, 1, MAX_READ_LINES)
    var start_index = start_line - 1
    if start_index >= lines.size():
        return {
            "ok": false,
            "error": "Offset %d is beyond end of file (%d lines)." % [start_line, lines.size()],
            "total_lines": lines.size(),
            "bytes_total": full.to_utf8_buffer().size()
        }
    var end_index = mini(start_index + bounded_limit, lines.size())
    var selected = PackedStringArray()
    for i in range(start_index, end_index):
        selected.append(lines[i])
    var truncated = end_index < lines.size()
    return {
        "ok": true,
        "content": "\n".join(selected),
        "line_start": start_line,
        "line_end": end_index,
        "total_lines": lines.size(),
        "truncated": truncated,
        "next_offset": end_index + 1 if truncated else 0,
        "bytes_total": full.to_utf8_buffer().size()
    }

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
    if _linked(relative_path): return _linked_path()
    if _reserved(relative_path): return _reserved_path()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f == null: return {"ok": false, "error": "Could not write file."}
    f.store_string(content)
    f.close()
    return {"ok": true, "bytes": content.to_utf8_buffer().size()}

func patch_file(relative_path: String, old_text: String, new_text: String) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    if _linked(relative_path): return _linked_path()
    if _reserved(relative_path): return _reserved_path()
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found."}
    if old_text == "":
        return {"ok": false, "error": "old_text cannot be empty."}
    # Never patch a read preview. Read the complete current file so untouched tail
    # content cannot be lost when a model edits a file larger than the read window.
    var full = FileAccess.get_file_as_string(path)
    var count = full.count(old_text)
    if count != 1:
        return {"ok": false, "error": "Patch requires exactly one match in the complete file; found %d." % count}
    var updated = full.replace(old_text, new_text)
    var result = write_file(relative_path, updated)
    if bool(result.get("ok", false)):
        result["bytes_before"] = full.to_utf8_buffer().size()
        result["bytes_after"] = updated.to_utf8_buffer().size()
        result["replacements"] = 1
    return result

func move_path(from_relative: String, to_relative: String) -> Dictionary:
    var from = _path(from_relative)
    var to = _path(to_relative)
    if from == "" or to == "": return _unsafe()
    if _linked(from_relative) or _linked(to_relative): return _linked_path()
    if _reserved(from_relative) or _reserved(to_relative): return _reserved_path()
    if not FileAccess.file_exists(from) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(from)):
        return {"ok": false, "error": "Source not found."}
    # Windows fails a rename onto an existing path while POSIX silently replaces
    # it, so refuse instead of letting a move destroy a file on one platform only.
    if FileAccess.file_exists(to) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(to)):
        return {"ok": false, "error": "Destination already exists. Delete or rename it first."}
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))
    var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
    return {"ok": err == OK, "error": "" if err == OK else "Move failed (%d)." % err}

func delete_path(relative_path: String) -> Dictionary:
    var path = _path(relative_path)
    if path == "": return _unsafe()
    if path == workspace: return _unsafe()
    if _linked(relative_path): return _linked_path()
    if _reserved(relative_path): return _reserved_path()
    var abs = ProjectSettings.globalize_path(path)
    if DirAccess.dir_exists_absolute(abs):
        var err_tree = _remove_tree_abs(abs)
        if err_tree == OK:
            return {"ok": true}
        return {"ok": false, "error": "Delete failed (%d). A file inside may still be open; stop the game and retry." % err_tree}
    if FileAccess.file_exists(path):
        var err = DirAccess.remove_absolute(abs)
        return {"ok": err == OK, "error": "" if err == OK else "Delete failed (%d)." % err}
    return {"ok": false, "error": "Path not found."}

func _path(relative_path: String) -> String:
    return PathUtils.join_workspace(workspace, relative_path)

func _unsafe() -> Dictionary:
    return {"ok": false, "error": "Unsafe path. Tools are limited to the current game workspace."}

func _linked_path() -> Dictionary:
    return {"ok": false, "error": "Unsafe path. Symbolic links and junctions inside the workspace are not followed."}

func _reserved_path() -> Dictionary:
    return {"ok": false, "error": "GameSmith reserves .git metadata; use the Git tools instead."}

# Lexical containment is not enough: a link inside the workspace can point
# outside it, and following one would let a file tool read or delete foreign
# files. Check every existing component because a parent may be the link.
func _linked(relative_path: String) -> bool:
    var safe = PathUtils.safe_relative_path(relative_path)
    if safe == "": return false
    var current = workspace
    for part in safe.split("/", false):
        var dir = DirAccess.open(current)
        if dir == null: return false
        if dir.is_link(part): return true
        current = current.path_join(part)
    return false

func _reserved(relative_path: String) -> bool:
    var safe = PathUtils.safe_relative_path(relative_path)
    if safe == "": return false
    for part in safe.split("/", false):
        if part.to_lower() == ".git": return true
    return false

func _walk(dir_path: String, root_path: String, out: Array[String]) -> void:
    var dir = DirAccess.open(dir_path)
    if dir == null: return
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        var full = dir_path.path_join(item)
        var rel = full.trim_prefix(root_path + "/")
        # Linked entries are not workspace content: a linked directory may
        # resolve outside the workspace and a linked file would be read through.
        if dir.is_link(item) or item == ".git":
            item = dir.get_next(); continue
        if dir.current_is_dir():
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
        # A normal directory may contain links to content outside the workspace.
        # Delete the link entry itself, never recurse into its target.
        if dir.is_link(item):
            var err_link = DirAccess.remove_absolute(child)
            if err_link != OK: return err_link
        elif dir.current_is_dir():
            var err = _remove_tree_abs(child)
            if err != OK: return err
        else:
            var err_file = DirAccess.remove_absolute(child)
            if err_file != OK: return err_file
        item = dir.get_next()
    dir.list_dir_end()
    return DirAccess.remove_absolute(abs)
