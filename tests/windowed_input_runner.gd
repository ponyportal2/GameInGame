extends SceneTree

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")

var failures := 0
var passed := 0

func _init() -> void:
    call_deferred("run")

func assert_true(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAIL: " + label)

func assert_eq(actual, expected, label: String) -> void:
    assert_true(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])

func run() -> void:
    var store = WorkspaceStoreScript.new(); store.ensure()
    var name = "Windowed Input Ownership"
    if name in store.list_games(): store.delete_game(name)
    var created: Dictionary = store.create_game(name)
    assert_true(bool(created.get("ok", false)), "creates windowed input regression workspace")
    if not created.get("ok", false):
        quit(1)
        return

    var source = """extends Node
var blocker: ColorRect
var ui_layer: CanvasLayer
func _ready():
    ui_layer = CanvasLayer.new()
    ui_layer.layer = 524287
    add_child(ui_layer)
    blocker = ColorRect.new()
    blocker.color = Color(0, 0, 0, 0)
    blocker.mouse_filter = Control.MOUSE_FILTER_STOP
    blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(blocker)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _input(_event):
    get_viewport().set_input_as_handled()
"""
    var f = FileAccess.open(created.path.path_join("main.gd"), FileAccess.WRITE)
    f.store_string(source); f.close()

    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    await process_frame; await process_frame
    assert_true(not app.chat_overlay.visible, "windowed generated game starts in gameplay")
    assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED, "generated game captures the real window mouse")
    assert_true(app.host_ui_canvas != null and app.host_ui_canvas.layer == app.HOST_UI_CANVAS_LAYER, "host UI lives in the reserved top CanvasLayer")
    assert_eq(app.runner.active_game.ui_layer.layer, app.HOST_UI_CANVAS_LAYER - 1, "generated max-layer UI is clamped below host UI on load")

    # Polling the InputMap action keeps host F1 ownership independent from generated _input handlers.
    Input.action_press("toggle_chat")
    await process_frame
    Input.action_release("toggle_chat")
    assert_true(app.chat_overlay.visible, "F1 host action still opens chat when generated game consumes _input")
    assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "F1 chat releases captured mouse for host controls")
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_IGNORE, "host chat disables high-layer generated GUI blocker")

    var settings_button = _find_button(app.chat_overlay, "Settings")
    assert_true(settings_button != null, "finds real chat Settings button")
    if settings_button != null:
        settings_button.emit_signal("pressed")
        await process_frame; await process_frame
        assert_true(app.settings_dialog.visible, "Settings opens visibly while gameplay tree is paused")
        assert_true(not (app.settings_dialog is Window), "Settings uses host-canvas overlay instead of modal subwindow")
        assert_true(app.settings_dialog.get_parent() == app.host_ui_root, "Settings overlay stays above generated game UI")
        var settings_close = _find_button(app.settings_dialog, "Close")
        assert_true(settings_close != null, "finds in-canvas Settings Close button")
        if settings_close != null:
            settings_close.emit_signal("pressed")
            await process_frame
            assert_true(not app.settings_dialog.visible, "Settings closes without freezing host input")
            assert_true(app.chat_overlay.visible, "closing Settings returns to the still-live chat overlay")
            assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Settings round-trip keeps generated input suspended behind chat")

    var close = _find_button(app.chat_overlay, "Close  Esc")
    assert_true(close != null, "finds real chat Close button")
    if close != null:
        var point: Vector2 = close.get_global_rect().get_center()
        var motion = InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
        Input.parse_input_event(motion)
        var down = InputEventMouseButton.new(); down.position = point; down.global_position = point; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
        Input.parse_input_event(down)
        var up = InputEventMouseButton.new(); up.position = point; up.global_position = point; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
        Input.parse_input_event(up)
        await process_frame; await process_frame
        assert_true(not app.chat_overlay.visible, "real chat button remains clickable above hostile generated UI")
        assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "closing chat restores generated GUI blocker")
        assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED, "closing chat restores gameplay mouse capture")

    # Regression: returning from a generated game must leave New Game as host-canvas
    # UI, not a modal Window that can own focus invisibly and make the main window
    # appear frozen.
    Input.action_press("toggle_chat")
    await process_frame
    Input.action_release("toggle_chat")
    assert_true(app.chat_overlay.visible, "chat can reopen before returning to library")
    app._return_to_library()
    await process_frame; await process_frame
    assert_eq(app.current_game, "", "returning from game clears current game")
    assert_true(app.library_layer.visible, "library is visible after returning from game")
    assert_true(not paused, "returning from game leaves SceneTree unpaused")

    var new_game = _find_button(app.library_layer, "+ New Game")
    assert_true(new_game != null, "library exposes New Game after returning from gameplay")
    if new_game != null:
        new_game.emit_signal("pressed")
        await process_frame
        assert_true(app.new_game_dialog.visible, "New Game UI opens after returning from gameplay")
        assert_true(not (app.new_game_dialog is Window), "New Game UI is not a modal/native Window")
        assert_true(app.new_game_dialog.get_parent() == app.host_ui_root, "New Game UI lives in the always-active host canvas")

    app.queue_free()
    paused = false
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    await process_frame
    store.delete_game(name)
    print("WINDOWED INPUT TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

func _find_button(node: Node, text: String) -> Button:
    if node is Button and node.text == text:
        return node
    for child in node.get_children():
        var found = _find_button(child, text)
        if found != null:
            return found
    return null
