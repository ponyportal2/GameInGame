extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
var config: Dictionary
var runner: Node
var finishing := false
var watchdog = preload("res://src/core/test_game_watchdog.gd").new()

func _init() -> void:
    var args = OS.get_cmdline_user_args()
    if not args.is_empty():
        config = JsonStore.read_dict(args[0], {})
    if not config.is_empty() and config.has("parent_pid"):
        watchdog.start(config)
    # Apply before deferred game startup; never raise the test window for actions.
    if config.get("mode") == "rendered":
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    call_deferred("start")

func start() -> void:
    var args = OS.get_cmdline_user_args()
    if args.is_empty():
        quit(2)
        return
    config = JsonStore.read_dict(args[0], {})
    if config.is_empty():
        quit(2)
        return
    if config.mode == "rendered":
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
        DisplayServer.window_set_title("GameSmith test — " + str(config.game))
    runner = Runner.new()
    root.add_child(runner)
    runner.runtime_log.start(config.game, config.workspace, {"root_path": config.diagnostics_root, "execution": {"kind": "test", "run_id": config.run_id, "mode": config.mode}})
    # Persist the diagnostic session before generated startup can hang or crash.
    _status("starting")
    var result = runner.load_game(config.workspace)
    _status("running" if result.ok else "failed", {"load_result": result})
    if not result.ok:
        finish(1)

func _process(_delta: float) -> bool:
    if finishing or config.is_empty() or runner == null:
        return false
    if config.mode == "rendered" and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    if FileAccess.file_exists(config.control_dir.path_join("stop.json")):
        finish(0)
        return false
    var path: String = config.control_dir.path_join("action.json")
    if FileAccess.file_exists(path):
        var action = JsonStore.read_dict(path, {})
        DirAccess.remove_absolute(path)
        perform_action(action)
    return false

func _status(state: String, extra: Dictionary = {}) -> void:
    var value = {"state": state, "session_id": runner.runtime_log.session_id, "session_path": runner.runtime_log.session_path, "user_data": OS.get_user_data_dir()}
    value.merge(extra)
    JsonStore.write_dict(config.control_dir.path_join("status.json"), value)

func finish(code: int) -> void:
    finishing = true
    runner.runtime_log.add("test_exit", "Test process exiting with code %d" % code)
    var status = JsonStore.read_dict(config.control_dir.path_join("status.json"), {})
    status.merge({"state": "exited", "graceful_exit": true}, true)
    # Execute generated cleanup before closing diagnostics.
    runner.free()
    watchdog.close()
    JsonStore.write_dict(config.control_dir.path_join("status.json"), status)
    quit(code)

func _finalize() -> void:
    watchdog.close()

func perform_action(args: Dictionary) -> void:
    var result: Dictionary = {"ok": false, "error": "Unknown test action."}
    var game: Node = runner.active_game
    var node: Node = game if str(args.get("path", "")) == "" else game.get_node_or_null(str(args.path))
    if node != null and node != game and not game.is_ancestor_of(node):
        node = null
    match str(args.get("action", "")):
        "inspect":
            if node != null:
                var children: Array = []
                for child in node.get_children().slice(0, 100):
                    children.append({"name": child.name, "class": child.get_class()})
                var properties: Dictionary = {}
                for property in args.get("properties", []).slice(0, 32):
                    properties[str(property)] = str(node.get(str(property))).left(1000)
                result = {"ok": true, "class": node.get_class(), "children": children, "properties": properties}
            else:
                result = {"ok": false, "error": "Game node not found."}
        "call":
            if node != null and node.has_method(str(args.get("method", ""))):
                result = {"ok": true, "value": str(node.callv(str(args.method), args.get("arguments", []))).left(4000)}
            else:
                result = {"ok": false, "error": "Game method not found."}
        "input":
            var event = InputEventAction.new()
            event.action = str(args.get("input_action", ""))
            event.pressed = bool(args.get("pressed", true))
            event.strength = 1.0 if event.pressed else 0.0
            if InputMap.has_action(event.action):
                Input.parse_input_event(event)
                result = {"ok": true}
            else:
                result = {"ok": false, "error": "Input action not found."}
        "screenshot":
            if config.mode != "rendered":
                result = {"ok": false, "error": "Screenshots require rendered testing."}
            else:
                # Minimized windows skip ordinary drawing. Render explicitly without
                # presenting a frame or restoring/focusing the native window.
                RenderingServer.force_draw(false)
                var bytes = root.get_texture().get_image().save_png_to_buffer()
                # Keep the test minimized after explicit capture as well.
                DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
                result = {"ok": true, "image_base64": Marshalls.raw_to_base64(bytes), "mime_type": "image/png"}
    result.action_id = args.get("action_id", "")
    result.pending = false
    JsonStore.write_dict(config.control_dir.path_join("action-result.json"), result)
