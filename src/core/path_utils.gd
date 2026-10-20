class_name PathUtils
extends RefCounted

# Windows refuses these device names for files and directories, even with an
# extension. Keep the check case-insensitive because NTFS is.
const RESERVED_DEVICE_NAMES = ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]
const FORBIDDEN_NAME_CHARACTERS = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
const MAX_GAME_NAME_LENGTH = 64

static func sanitize_game_name(raw: String) -> String:
    var s = raw.strip_edges()
    var out = ""
    var previous_space = false
    for i in s.length():
        var ch = s.substr(i, 1)
        var code = ch.unicode_at(0)
        # Control characters (including DEL) cannot be shown or typed back.
        var safe = code >= 32 and code != 127 and ch not in FORBIDDEN_NAME_CHARACTERS
        if not safe:
            ch = " "
        if ch == " ":
            if previous_space:
                continue
            previous_space = true
        else:
            previous_space = false
        out += ch
    out = _trim_name_edges(out)
    # A leading dot makes the workspace a hidden directory, and the library
    # skips hidden directories, so the game would exist but never be listed.
    while out.begins_with("."):
        out = _trim_name_edges(out.substr(1))
    if out == "":
        return "Untitled Game"
    if _is_reserved_device_name(out):
        out = "Game " + out
    out = out.left(MAX_GAME_NAME_LENGTH)
    # Truncation can expose a trailing dot or space that Windows rejects.
    out = _trim_name_edges(out)
    if out == "":
        return "Untitled Game"
    return out

static func _trim_name_edges(value: String) -> String:
    # Windows silently drops trailing dots and spaces, so two different names
    # could otherwise resolve to the same directory.
    var out = value.strip_edges()
    while out.ends_with("."):
        out = out.substr(0, out.length() - 1).strip_edges()
    return out

static func _is_reserved_device_name(value: String) -> bool:
    # Windows treats "con", "con.txt" and "con.old.game" as the same device.
    return value.get_slice(".", 0).strip_edges().to_lower() in RESERVED_DEVICE_NAMES

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
