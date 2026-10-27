extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
var config: Dictionary
var runner: Node
var finishing := false
var smoke_pending := false
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
    if not result.ok:
        _status("failed", {"load_result": result})
        finish(1)
        return
    _status("starting", {"load_result": result})
    var smoke = await _measure_smoke_window()
    if finishing: return
    _status("running" if smoke.ok else "failed", {"load_result": result, "startup_smoke": smoke})
    if not smoke.ok:
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
    var status_path: String = config.control_dir.path_join("status.json")
    if not JsonStore.write_dict(status_path, status):
        # The final status is the only proof of a graceful stop. Never quit
        # without publishing it when the atomic replacement stayed blocked.
        var file = FileAccess.open(status_path, FileAccess.WRITE)
        if file == null:
            push_error("Test process could not publish final status: %s" % error_string(FileAccess.get_open_error()))
        else:
            file.store_string(JSON.stringify(status, "  "))
            file.flush()
            var write_error = file.get_error()
            file.close()
            if write_error != OK:
                push_error("Test process final status write failed: %s" % error_string(write_error))
    quit(code)

func _finalize() -> void:
    watchdog.close()

func perform_action(args: Dictionary) -> void:
    if args.get("action") in ["smoke", "inject_child"]:
        if not smoke_pending:
            smoke_pending = true
            _smoke_window(args)
        return
    var result: Dictionary = {"ok": false, "error": "Unknown test action."}
    var game: Node = runner.active_game
    var node: Node = game if str(args.get("path", "")) == "" else game.get_node_or_null(str(args.path))
    if node != null and node != game and not game.is_ancestor_of(node):
        node = null
    match str(args.get("action", "")):
        "inspect":
            if node != null:
                var description = _describe_node(node, game, clampi(int(args.get("depth", 1)), 0, 4), [100])
                var properties: Dictionary = {}
                for property in args.get("properties", []).slice(0, 32):
                    properties[str(property)] = str(node.get(str(property))).left(1000)
                result = description
                result.merge({"ok": true, "properties": properties})
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
        "mouse_button":
            var button = args.get("button_index", 0)
            var position = args.get("position", {"x": 0, "y": 0})
            if not (button is int or button is float) or float(button) != int(button) or int(button) < 1 or int(button) > 9 or not args.get("pressed", true) is bool:
                result = {"ok": false, "error": "button_index must be an integer from 1 to 9; pressed must be boolean."}
            elif not position is Dictionary or position.size() != 2 or not (position.get("x") is float or position.get("x") is int) or not (position.get("y") is float or position.get("y") is int) or not is_finite(float(position.x)) or not is_finite(float(position.y)):
                result = {"ok": false, "error": "position must contain finite numeric x and y."}
            else:
                var event = InputEventMouseButton.new()
                event.button_index = int(button)
                event.pressed = args.get("pressed", true)
                event.position = Vector2(position.x, position.y)
                event.global_position = event.position
                event.button_mask = (1 << (int(button) - 1)) if event.pressed else 0
                Input.parse_input_event(event)
                result = {"ok": true}
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
    if node == null and str(args.get("action", "")) in ["inspect", "call"]:
        result.path_hint = "Use paths returned by inspect, relative to the game root. Empty path or '.' selects the game root; preserve '@' in generated names."
        result.requested_path = str(args.get("path", ""))
        result.available_children = _describe_node(game, game, 1, [10]).get("children", []) if game != null else []
    result.action_id = args.get("action_id", "")
    result.pending = false
    JsonStore.write_dict(config.control_dir.path_join("action-result.json"), result)

func _describe_node(node: Node, game: Node, depth: int, budget: Array) -> Dictionary:
    budget[0] -= 1
    var children: Array = []
    if depth > 0:
        for child in node.get_children():
            if budget[0] <= 0: break
            children.append(_describe_node(child, game, depth - 1, budget))
    return {"name": str(node.name), "path": str(game.get_path_to(node)), "class": node.get_class(), "children": children, "child_count": node.get_child_count(), "children_truncated": children.size() < node.get_child_count()}

func _smoke_window(args: Dictionary) -> void:
    var inserted_handle: Dictionary = {}
    var inserted_parent: WeakRef
    if args.get("action") == "inject_child":
        var helper = preload("res://src/core/runtime_properties.gd").new(runner)
        var parent = helper._path(runner.active_game, args.get("candidate_path"))
        var Children = preload("res://src/core/runtime_children.gd")
        var fields: Dictionary = {}
        for key in ["candidate_path", "name", "script_path", "properties"]:
            if args.has(key): fields[key] = args[key]
        var injection = Children.validate(config.workspace, fields)
        for key in args:
            if key not in ["action", "action_id", "run_id", "parent", "candidate_path", "name", "script_path", "properties", "expected"]:
                injection = Children.error("invalid_arguments", "Unknown injection argument: " + str(key) + "; use candidate_path for the detached parent.")
        if injection.ok:
            fields.expected = args.get("expected", {"class": parent.get_class(), "script": Children.script_path(parent)} if parent != null else {})
            # Explicit script checks use workspace-relative paths in public actions.
            if fields.expected is Dictionary and fields.expected.get("script", "") != "" and not str(fields.expected.script).is_absolute_path():
                fields.expected.script = ProjectSettings.globalize_path(config.workspace.path_join(fields.expected.script))
            if not fields.expected is Dictionary or fields.expected.size() != 2 or not fields.expected.get("class") is String or not fields.expected.get("script") is String:
                injection = Children.error("parent_mismatch", "expected requires class and workspace-relative script.")
            else:
                injection = Children.insert(runner, config.workspace, parent, fields)
        if not injection.ok:
            injection.action_id = args.action_id
            injection.pending = false
            JsonStore.write_dict(config.control_dir.path_join("action-result.json"), injection)
            smoke_pending = false
            return
        inserted_handle = injection.handle
        inserted_parent = weakref(parent)
    var result = await _measure_smoke_window()
    if finishing: return
    if not inserted_handle.is_empty():
        var helper = preload("res://src/core/runtime_properties.gd").new(runner)
        var child = helper._resolve(inserted_handle, runner.active_game)
        var parent = helper._path(runner.active_game, args.get("candidate_path"))
        if child == null or parent == null or parent != inserted_parent.get_ref() or child.get_parent() != parent or str(child.name) != args.name:
            result.ok = false
            result.reason = "injected_child_changed"
            result.error = "Injected child did not survive smoke with its expected identity, parent and name."
    if not inserted_handle.is_empty(): result.handle = inserted_handle
    result.action_id = args.action_id
    result.pending = false
    JsonStore.write_dict(config.control_dir.path_join("action-result.json"), result)
    smoke_pending = false

func _measure_smoke_window() -> Dictionary:
    var process_start = Engine.get_process_frames()
    var physics_start = Engine.get_physics_frames()
    var process_completed := 0
    var physics_completed := 0
    # Frame signals precede callbacks. Exclude the current frame/tick so the
    # result only counts execution that has already returned to the next frame.
    while process_completed < 4 or physics_completed < 3:
        await process_frame
        if finishing: return {"ok": false, "reason": "cancelled"}
        process_completed = maxi(0, Engine.get_process_frames() - process_start - 1)
        physics_completed = maxi(0, Engine.get_physics_frames() - physics_start - 1)
    runner.runtime_log.mutex.lock()
    var errors = int(runner.runtime_log.notification_counts.error)
    runner.runtime_log.mutex.unlock()
    var result = {"ok": errors == 0, "reason": "passed" if errors == 0 else "execution_errors", "process_ticks_completed": process_completed, "physics_ticks_completed": physics_completed, "errors": errors}
    if errors > 0:
        result.error = "Test emitted errors during startup or smoke execution."
    return result
