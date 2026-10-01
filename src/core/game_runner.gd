class_name GameRunner
extends Node

signal load_succeeded(version: int)
signal load_failed(message: String)

var active_game: Node
var active_source_path = ""
var runtime_log = RuntimeLog.new()

func load_game(workspace: String) -> Dictionary:
    var main_path = workspace.path_join("main.gd")
    if not FileAccess.file_exists(main_path):
        var msg = "No main.gd exists yet. Ask the agent to create the game first."
        runtime_log.add("load", msg)
        load_failed.emit(msg)
        return {"ok": false, "error": msg}

    var source = FileAccess.get_file_as_string(main_path)
    var script = GDScript.new()
    script.resource_path = "%s#candidate-%d" % [main_path, Time.get_ticks_usec()]
    script.source_code = source
    var compile_error = script.reload()
    if compile_error != OK:
        var msg = "main.gd failed to compile (error %d). Previous game kept running." % compile_error
        runtime_log.add("compile", msg)
        load_failed.emit(msg)
        return {"ok": false, "error": msg}

    var candidate = script.new()
    if candidate == null or not (candidate is Node):
        var msg = "main.gd must extend a Godot Node type. Previous game kept running."
        runtime_log.add("instantiate", msg)
        load_failed.emit(msg)
        return {"ok": false, "error": msg}

    if is_instance_valid(active_game):
        active_game.get_parent().remove_child(active_game)
        active_game.queue_free()
    active_game = candidate
    active_source_path = main_path
    add_child(active_game)
    var version = runtime_log.next_version()
    runtime_log.add("load", "Loaded %s" % main_path)
    load_succeeded.emit(version)
    return {"ok": true, "version": version}

func unload_game() -> void:
    if is_instance_valid(active_game):
        active_game.queue_free()
    active_game = null
    active_source_path = ""

func has_active_game() -> bool:
    return is_instance_valid(active_game)
