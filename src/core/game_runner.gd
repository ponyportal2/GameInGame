class_name GameRunner
extends Node

signal load_succeeded(version: int)
signal load_failed(message: String)

var active_game: Node
var active_source_path = ""
var runtime_log = RuntimeLog.new()
var dependency_paths: Array[String] = []

func _exit_tree() -> void:
    runtime_log.close()

func load_game(workspace: String) -> Dictionary:
    if runtime_log.session_id == "":
        runtime_log.start(workspace.get_file(), workspace)
    runtime_log.begin_attempt(workspace)
    var main_path = workspace.path_join("main.gd")
    if not FileAccess.file_exists(main_path):
        var msg = "No main.gd exists yet. Ask the agent to create the game first."
        return _reject("load", msg)

    # Install fresh dependency resources without mutating scripts used by the
    # active game. On rejection, restore the old resource cache as well as the game.
    var paths: Array[String] = []
    _collect_scripts(workspace, paths)
    paths.erase(main_path)
    var previous: Dictionary = {}
    var dependencies: Array[GDScript] = []
    for path in dependency_paths + paths:
        if not previous.has(path):
            previous[path] = ResourceLoader.get_cached_ref(path)
            if previous[path] != null:
                previous[path].resource_path = ""
    for path in paths:
        # Unreferenced drafts are not part of this game's load. New dependencies
        # will load normally; only resources already in the cache need replacement.
        if previous.get(path) == null:
            continue
        var dependency = GDScript.new()
        dependency.source_code = FileAccess.get_file_as_string(path)
        dependency.take_over_path(path)
        dependencies.append(dependency)

    for dependency in dependencies:
        if dependency.reload() != OK:
            break
    var source = FileAccess.get_file_as_string(main_path)
    var script = GDScript.new()
    script.resource_path = "%s#candidate-%d" % [main_path, Time.get_ticks_usec()]
    runtime_log.set_candidate_path(script.resource_path)
    script.source_code = source
    var compile_error = script.reload()
    if compile_error != OK or runtime_log.startup_message() != "":
        _restore_cache(previous, dependencies)
        return _reject("compile", "Game failed to compile. Previous game kept running.\n" + runtime_log.startup_message())

    var previous_mouse_mode = Input.mouse_mode
    runtime_log.set_phase("startup")
    var candidate = script.new()
    if candidate == null or not (candidate is Node):
        if candidate is Object and not candidate is RefCounted:
            candidate.free()
        _restore_cache(previous, dependencies)
        Input.mouse_mode = previous_mouse_mode
        return _reject("instantiate", "main.gd must extend a Godot Node type. Previous game kept running.")

    # _enter_tree/_ready run synchronously. Keep the active game until startup
    # completes, and reject candidates that logged script/runtime errors.
    add_child(candidate)
    if runtime_log.startup_message() != "" or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
        if is_instance_valid(candidate):
            if candidate.get_parent() == self:
                remove_child(candidate)
            candidate.queue_free()
        Input.mouse_mode = previous_mouse_mode
        _restore_cache(previous, dependencies)
        return _reject("startup", "Game failed during startup. Previous game kept running.\n" + runtime_log.startup_message())

    if is_instance_valid(active_game):
        active_game.get_parent().remove_child(active_game)
        active_game.queue_free()
    active_game = candidate
    active_source_path = main_path
    dependency_paths = paths
    var result = runtime_log.finish_attempt(true, "load", "Loaded %s" % main_path)
    var version = runtime_log.load_version
    load_succeeded.emit(version)
    result.merge({"ok": true, "version": version})
    return result

func _reject(kind: String, message: String) -> Dictionary:
    var result = runtime_log.finish_attempt(false, kind, message)
    load_failed.emit(message)
    result.merge({"ok": false, "error": message})
    return result

func _restore_cache(previous: Dictionary, dependencies: Array[GDScript]) -> void:
    for dependency in dependencies:
        dependency.resource_path = ""
    for path in previous:
        if previous[path] != null:
            previous[path].take_over_path(path)

func _collect_scripts(directory: String, paths: Array[String]) -> void:
    var dir = DirAccess.open(directory)
    if dir == null:
        return
    for file in dir.get_files():
        if file.get_extension() == "gd":
            paths.append(directory.path_join(file))
    for child in dir.get_directories():
        if child not in [".git", ".godot"] and not dir.is_link(child):
            _collect_scripts(directory.path_join(child), paths)

func unload_game() -> void:
    if is_instance_valid(active_game):
        active_game.queue_free()
    active_game = null
    active_source_path = ""

func has_active_game() -> bool:
    return is_instance_valid(active_game)
