extends RefCounted

# All retention mutations stay beneath this game's test metadata directory.
const BUDGET_BYTES = 64 * 1024 * 1024
const MAX_HISTORY = 128

static func recover_all() -> void:
    var games = ProjectSettings.globalize_path("user://host/games")
    var dir = DirAccess.open(games)
    if dir != null:
        for game in dir.get_directories():
            if not dir.is_link(game):
                recover(games.path_join(game).path_join("tests"))

static func recover(root: String) -> void:
    var dir = DirAccess.open(root)
    if dir == null:
        return
    for id in dir.get_directories():
        if id == "runtime" or dir.is_link(id):
            continue
        var path = root.path_join(id)
        var outcome = JsonStore.read_dict(path.path_join("outcome.json"), {})
        if outcome.get("state") == "exited":
            continue
        var config = JsonStore.read_dict(path.path_join("config.json"), {})
        if config.get("run_id") != id:
            continue
        var heartbeat_path = path.path_join("parent-heartbeat")
        var heartbeat = FileAccess.get_file_as_string(heartbeat_path).split(":") if FileAccess.file_exists(heartbeat_path) else PackedStringArray()
        if heartbeat.size() == 2 and heartbeat[0] == config.get("parent_token") and Time.get_unix_time_from_system() - float(heartbeat[1]) < 15:
            continue # Another live host owns this run; never kill a saved PID.
        var child = JsonStore.read_dict(path.path_join("status.json"), {})
        var watchdog = JsonStore.read_dict(path.path_join("watchdog.json"), {})
        var confirmed_exit = watchdog.get("method") == "forced" or child.get("state") == "exited"
        outcome.merge({
            "ok": true, "run_id": id, "mode": config.get("mode", "headless"), "path": path,
            "state": "exited" if confirmed_exit else "interrupted",
            "stop_method": "graceful" if child.get("graceful_exit", false) else str(watchdog.get("method", "owner_lost")),
            "stop_reason": "Recovered interrupted test; " + str(watchdog.get("reason", "parent watchdog cleanup pending"))
        }, true)
        JsonStore.write_dict(path.path_join("outcome.json"), outcome)

static func size_bytes(path: String) -> int:
    var dir = DirAccess.open(path)
    if dir == null:
        var file = FileAccess.open(path, FileAccess.READ)
        return file.get_length() if file != null else 0
    var total := 0
    for entry in dir.get_files():
        if not dir.is_link(entry):
            total += size_bytes(path.path_join(entry))
    for entry in dir.get_directories():
        if not dir.is_link(entry):
            total += size_bytes(path.path_join(entry))
    return total

static func remove_tree(root: String, path: String) -> bool:
    var target = path.simplify_path()
    if not target.begins_with(root.simplify_path().trim_suffix("/") + "/"):
        return false
    var parent = DirAccess.open(target.get_base_dir())
    if parent == null:
        return false
    if parent.is_link(target.get_file()):
        return DirAccess.remove_absolute(target) == OK
    var dir = DirAccess.open(target)
    if dir != null:
        for entry in dir.get_files():
            if not remove_tree(root, target.path_join(entry)):
                return false
        for entry in dir.get_directories():
            if not remove_tree(root, target.path_join(entry)):
                return false
    return DirAccess.remove_absolute(target) == OK

static func enforce(root: String, active: Array, budget: int = BUDGET_BYTES) -> Dictionary:
    var index = JsonStore.read_dict(root.path_join("retention.json"), {"expired": []})
    var dir = DirAccess.open(root)
    if dir == null:
        return index
    var total = size_bytes(root)
    var entries = dir.get_directories()
    entries.sort()
    for id in entries:
        if total <= budget:
            break
        if id == "runtime" or id in active or dir.is_link(id):
            continue
        var path = root.path_join(id)
        var outcome = JsonStore.read_dict(path.path_join("outcome.json"), {})
        if outcome.get("state") != "exited":
            continue
        var child = JsonStore.read_dict(path.path_join("status.json"), {})
        if not remove_tree(root, path):
            index.write_failure = "Could not remove expired test evidence: " + id
            continue
        var session = str(child.get("session_id", ""))
        if session != "" and session == session.get_file() and not session.begins_with(".") and not session.contains("\\") and not session.contains(":"):
            remove_tree(root, root.path_join("runtime").path_join(session))
        index.expired.append({"run_id": id, "reason": "test_storage_budget", "utc": Time.get_datetime_string_from_system(true) + "Z"})
        if index.expired.size() > MAX_HISTORY:
            index.expired.pop_front()
            index.older_expirations = int(index.get("older_expirations", 0)) + 1
        total = size_bytes(root)
    index.bytes = total
    index.budget_bytes = budget
    if not JsonStore.write_dict(root.path_join("retention.json"), index):
        index.write_failure = "Could not persist test retention index."
    return index
