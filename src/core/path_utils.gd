class_name PathUtils
extends RefCounted

static func sanitize_game_name(raw: String) -> String:
    var s = raw.strip_edges()
    var out = ""
    var previous_space = false
    for i in s.length():
        var ch = s.substr(i, 1)
        var code = ch.unicode_at(0)
        var safe = code >= 32 and ch not in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        if not safe:
            ch = " "
        if ch == " ":
            if previous_space:
                continue
            previous_space = true
        else:
            previous_space = false
        out += ch
    out = out.strip_edges().trim_suffix(".")
    if out in ["", ".", ".."]:
        return "Untitled Game"
    return out.left(64)

static func safe_relative_path(relative_path: String) -> String:
    var p = relative_path.replace("\\", "/").strip_edges()
    if p == "" or p.begins_with("/") or p.contains(":"):
        return ""
    var parts = p.split("/", false)
    var clean: Array[String] = []
    for part in parts:
        if part in ["", "."]:
            continue
        if part == "..":
            return ""
        clean.append(part)
    return "/".join(clean)

static func join_workspace(workspace: String, relative_path: String) -> String:
    var safe = safe_relative_path(relative_path)
    if safe == "":
        return ""
    return workspace.path_join(safe)
