class_name GitService
extends RefCounted

const AUTHOR_ARGS = ["-c", "user.name=GameSmith", "-c", "user.email=gamesmith@local.invalid"]

func available() -> bool:
    var output: Array = []
    return OS.execute("git", ["--version"], output, true) == 0

func init_repo(path: String) -> Dictionary:
    var r = _run(path, ["init", "-q"])
    if not r.ok:
        return r
    _run(path, ["config", "user.name", "GameSmith"])
    _run(path, ["config", "user.email", "gamesmith@local.invalid"])
    return _run(path, AUTHOR_ARGS + ["commit", "--allow-empty", "-q", "-m", "Initialize game"])

func status(path: String) -> Dictionary:
    return _run(path, ["status", "--short", "--branch"])

func diff(path: String) -> Dictionary:
    return _run(path, ["diff", "--", "."])

func log(path: String, limit: int = 12) -> Dictionary:
    return _run(path, ["log", "--oneline", "--decorate", "-n", str(clampi(limit, 1, 50))])

func commit(path: String, message: String) -> Dictionary:
    var add = _run(path, ["add", "-A"])
    if not add.ok:
        return add
    var clean_message = message.strip_edges()
    if clean_message == "":
        clean_message = "Update generated game"
    return _run(path, AUTHOR_ARGS + ["commit", "--allow-empty", "-m", clean_message.left(120)])

func head(path: String) -> String:
    var r = _run(path, ["rev-parse", "HEAD"])
    return r.output.strip_edges() if r.ok else ""

func _run(path: String, args: Array) -> Dictionary:
    var output: Array = []
    var full: Array = ["-C", ProjectSettings.globalize_path(path)]
    full.append_array(args)
    var code = OS.execute("git", full, output, true)
    return {"ok": code == 0, "code": code, "output": "\n".join(output)}
