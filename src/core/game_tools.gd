class_name GameTools
extends RefCounted

signal blender_approval_changed(review: Dictionary)

const DEFAULT_READ_LINES = 300
const MAX_READ_LINES = 1000

var workspace = ""
var git = GitService.new()
var runner: GameRunner
var test_supervisor: Node
var blender_supervisor: Node
var blender_enabled := true
var image_supervisor: Node
var reload_token := 0

func generate_image(args: Dictionary) -> Dictionary:
    if not is_instance_valid(image_supervisor):
        image_supervisor = preload("res://src/core/image_generation.gd").new()
        runner.add_child(image_supervisor)
    return image_supervisor.execute(workspace, args)

func blender(args: Dictionary) -> Dictionary:
    if not blender_enabled:
        return {"ok": false, "error": "Blender tools are disabled for this game. Enable them in Settings > This game."}
    if not is_instance_valid(blender_supervisor):
        blender_supervisor = preload("res://src/core/blender_supervisor.gd").new()
        blender_supervisor.approval_changed.connect(func(review): blender_approval_changed.emit(review))
        runner.add_child(blender_supervisor)
    return blender_supervisor.execute(workspace, args)

func tests() -> Node:
    if not is_instance_valid(test_supervisor):
        test_supervisor = preload("res://src/core/test_game_supervisor.gd").new()
        test_supervisor.rebind(workspace)
        runner.add_child(test_supervisor)
    return test_supervisor

func _init(p_workspace: String = "", p_runner: GameRunner = null):
    workspace = p_workspace
    runner = p_runner

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

func git_status() -> Dictionary: return git.status(workspace)
func git_diff() -> Dictionary: return git.diff(workspace)
func git_log(limit: int = 12) -> Dictionary: return git.log(workspace, limit)
func git_commit(message: String) -> Dictionary: return git.commit(workspace, message)

func reload_game(cancelled: Callable = Callable()) -> Dictionary:
    if not is_instance_valid(runner): return {"ok": false, "error": "Runner unavailable."}
    var result := {"ok": true, "pending": true}
    _perform_reload(result, reload_token, cancelled)
    return result

func cancel_reload() -> void:
    reload_token += 1

func wait_reload(result: Dictionary) -> Dictionary:
    while result.get("pending", false):
        if not is_instance_valid(runner) or not runner.is_inside_tree():
            return {"ok": false, "reason": "runner_unavailable", "error": "Runner unavailable."}
        await runner.get_tree().process_frame
    return result

func _perform_reload(pending: Dictionary, token: int, cancelled: Callable) -> void:
    var result: Dictionary = await runner.checked_reload(workspace, func(): return token != reload_token or (cancelled.is_valid() and cancelled.call()))
    if result.has("attempt_id"):
        result.diagnostics = runner.runtime_log.read({"attempt": result.attempt_id, "limit": 20}, true)
        result.delivery_id = result.diagnostics.get("delivery_id", "")
        result.diagnostics.erase("delivery_id")
    elif result.has("preflight"):
        # Preserve the existing tool-level diagnostics contract on rejection.
        result.diagnostics = result.preflight.get("diagnostics", {}).duplicate(true)
    pending.merge(result, true)
    pending.pending = false

func read_runtime_log(args: Dictionary = {}) -> Dictionary:
    if runner == null: return {"ok": false, "error": "Runner unavailable."}
    return runner.runtime_log.read(args, true)

func runtime_child(command: String, args: Dictionary) -> Dictionary:
    var pending := {"ok": true, "pending": true}
    _perform_runtime_child(pending, command, args.duplicate(true), reload_token)
    return pending

func _perform_runtime_child(pending: Dictionary, command: String, args: Dictionary, token: int) -> void:
    # Always leave the current callback/physics stack before structural mutation.
    if not is_instance_valid(runner) or not runner.is_inside_tree():
        pending.merge({"ok": false, "pending": false, "error": "Runner unavailable.", "live_attempted": false})
        return
    await runner.get_tree().process_frame
    var result: Dictionary = await _checked_runtime_child(command, args, token)
    pending.merge(result, true)
    pending.pending = false

func _checked_runtime_child(command: String, args: Dictionary, token: int) -> Dictionary:
    var Children = preload("res://src/core/runtime_children.gd")
    var helper = preload("res://src/core/runtime_properties.gd").new(runner)
    var rejected = {"ok": false, "live_attempted": false, "live_game_modified": false, "temporary": true}
    if token != reload_token:
        rejected.merge(Children.error("cancelled", "Runtime operation cancelled."), true)
        return rejected
    var game = helper._game()
    var target = args.get("parent" if command == "add_runtime_child" else "target", {})
    if game == null or not target is Dictionary or target.size() != 3 or not target.get("path") is String or target.path.length() > 1024 or not target.get("instance_id") is String or not target.get("game_generation") is String:
        rejected.merge(Children.error("invalid_handle", "Copy an exact current handle from inspect_runtime."), true)
        return rejected
    var node = helper._resolve(target, game)
    if node == null:
        rejected.merge(Children.error("stale_handle", "Stale target or target outside active_game. Inspect again."), true)
        return rejected
    if runner.reload_in_progress:
        rejected.merge(Children.error("operation_in_progress", "A reload or structural operation is already in progress."), true)
        return rejected
    if command == "remove_runtime_child":
        var owned = runner.runtime_children.get(node.get_instance_id())
        if args.size() != 1 or owned == null or owned.get_ref() != node:
            rejected.merge(Children.error("not_injected", "Removal is limited to nodes added by add_runtime_child."), true)
            return rejected
        var before = Children.errors(runner)
        var id = node.get_instance_id()
        node.get_parent().remove_child(node)
        if is_instance_valid(node): node.queue_free()
        runner.runtime_children.erase(id)
        var clean = Children.errors(runner) == before
        return {"ok": clean, "live_attempted": true, "live_game_modified": true if clean else null, "temporary": true, "removed": target, "note": "Removal does not undo the component's earlier side effects.", "error": "" if clean else "Errors occurred during removal; side effects may remain."}
    var valid = Children.validate(workspace, args)
    if not valid.ok:
        rejected.merge(valid, true)
        return rejected
    if node.get_node_or_null(NodePath(args.name)) != null:
        rejected.merge(Children.error("child_already_present", "Child name is already occupied in the live game."), true)
        return rejected
    var before = preload("res://src/core/reload_preflight.gd").fingerprint(workspace)
    if not before.ok:
        rejected.merge(Children.error("fingerprint_failed", "Cannot fingerprint workspace code/resources."), true)
        return rejected
    args.expected = {"class": node.get_class(), "script": Children.script_path(node)}
    var operation = args.duplicate(true)
    operation.action = "inject_child"
    runner.reload_in_progress = true
    var preflight: Dictionary = await preload("res://src/core/reload_preflight.gd").run(runner, workspace, func(): return token != reload_token, runner.preflight_timeout_ms, operation)
    var reason = ""
    if not preflight.ok: reason = str(preflight.get("reason", "preflight_failed"))
    elif token != reload_token: reason = "cancelled"
    elif helper._game() != game or helper._resolve(target, game) != node: reason = "stale_handle"
    elif not node.is_node_ready(): reason = "parent_not_ready"
    elif node.get_class() != args.expected.class or Children.script_path(node) != args.expected.script: reason = "parent_mismatch"
    elif node.get_node_or_null(NodePath(args.name)) != null: reason = "child_already_present"
    else:
        var after = preload("res://src/core/reload_preflight.gd").fingerprint(workspace)
        if not after.ok or after.files != before.files: reason = "code_changed"
    var result = rejected
    if reason != "":
        result.merge(Children.error(reason, "Late-insertion preflight rejected: " + reason), true)
    else:
        result = Children.insert(runner, workspace, node, args)
        result.live_attempted = true
        result.live_game_modified = true if result.ok else null
        result.temporary = true
    # Keep complete outcome identity even with large candidate diagnostics.
    # Full private preflight evidence remains on disk alongside reload evidence.
    var diagnostics: Dictionary = preflight.get("diagnostics", {})
    var cleanup: Dictionary = preflight.get("cleanup", {})
    result.preflight = {"ok": preflight.ok, "reason": preflight.get("reason", ""), "run_id": preflight.get("run_id", ""), "process_ticks_completed": preflight.get("process_ticks_completed", 0), "physics_ticks_completed": preflight.get("physics_ticks_completed", 0), "errors": preflight.get("errors", 0), "error": str(preflight.get("error", "")).left(1500), "cleanup": {"state": cleanup.get("state", "unknown"), "stop_method": cleanup.get("stop_method", ""), "exit_code": cleanup.get("exit_code", -1)}, "diagnostics": "\n".join(str(diagnostics.get("log", "")).split("\n").slice(0, 60)).left(6000)}
    runner.reload_in_progress = false
    return result

func execute(name: String, args: Dictionary) -> Dictionary:
    match name:
        "inspect_runtime": return preload("res://src/core/runtime_properties.gd").new(runner).inspect(args)
        "set_properties": return preload("res://src/core/runtime_properties.gd").new(runner).set_properties(args)
        "add_runtime_child", "remove_runtime_child": return runtime_child(name, args)
        "blender": return blender(args)
        "generate_image": return generate_image(args)
        "list_files": return list_files(str(args.get("path", "")))
        "read_file": return read_file(str(args.get("path", "")), int(args.get("offset", 1)), int(args.get("limit", DEFAULT_READ_LINES)))
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
        "read_runtime_log": return read_runtime_log(args)
        "start_test_game": return tests().start(workspace, str(args.get("mode", "headless")))
        "read_test_log": return tests().read_log(str(args.get("run_id", "")), args)
        "stop_test_game": return tests().request_stop(str(args.get("run_id", "")))
        "test_game_action": return tests().request_action(str(args.get("run_id", "")), args)
        _: return {"ok": false, "error": "Unknown tool: " + name}

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
