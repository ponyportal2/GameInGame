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
var gameplay_clicks := 0
func _ready():
    ui_layer = CanvasLayer.new()
    ui_layer.layer = 524287
    add_child(ui_layer)
    blocker = ColorRect.new()
    blocker.color = Color(0.08, 0.32, 0.16, 1)
    blocker.mouse_filter = Control.MOUSE_FILTER_STOP
    blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(blocker)
    blocker.gui_input.connect(func(event):
        if event is InputEventMouseButton and event.pressed:
            gameplay_clicks += 1
    )
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _input(event):
    if event is InputEventKey:
        get_viewport().set_input_as_handled()
"""
    var f = FileAccess.open(created.path.path_join("main.gd"), FileAccess.WRITE)
    f.store_string(source); f.close()

    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app._open_game(name)
    app._run_game()
    await process_frame; await process_frame
    assert_true(not app.chat_overlay.visible, "windowed generated game starts in gameplay")
    assert_eq(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED, "generated game captures the real window mouse")
    assert_true(app.host_ui_canvas != null and app.host_ui_canvas.layer == app.HOST_UI_CANVAS_LAYER, "host UI lives in the reserved top CanvasLayer")
    assert_eq(app.runner.active_game.ui_layer.layer, app.HOST_UI_CANVAS_LAYER - 1, "generated max-layer UI is clamped below host UI on load")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var game_click = InputEventMouseButton.new()
    game_click.position = Vector2(640, 600)
    game_click.global_position = game_click.position
    game_click.button_index = MOUSE_BUTTON_LEFT
    game_click.pressed = true
    Input.parse_input_event(game_click)
    game_click = game_click.duplicate()
    game_click.pressed = false
    Input.parse_input_event(game_click)
    await process_frame
    assert_eq(app.runner.active_game.gameplay_clicks, 1, "unoccupied host UI lets mouse input reach the playing game")
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

    var close = _find_button(app.chat_overlay, "Resume Game  Esc")
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

    # Capture must own input even when generated _input consumes every key.
    var pen_key := InputEventKey.new()
    pen_key.keycode = KEY_S
    pen_key.physical_keycode = KEY_S
    pen_key.ctrl_pressed = true
    pen_key.shift_pressed = true
    pen_key.pressed = true
    Input.parse_input_event(pen_key)
    for i in 60:
        await process_frame
        if app.annotation_editor.visible: break
    pen_key = pen_key.duplicate()
    pen_key.pressed = false
    Input.parse_input_event(pen_key)
    assert_true(app.annotation_editor.visible, "Ctrl+Shift+S opens the frozen pen editor above hostile generated input")
    assert_true(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "marking pauses gameplay and releases the captured mouse")
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("user://annotation-editor.png")
    var screenshot: Image = app.annotation_editor.canvas.picture
    if screenshot != null:
        var pixel := screenshot.get_pixel(40, 40)
        assert_true(pixel.g > 0.28 and pixel.r < 0.12, "captured PNG contains the game rather than host HUD or editor")
    else:
        assert_true(false, "capture produced a real screenshot")
    app._cancel_annotation()
    assert_true(not paused and not app.chat_overlay.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "cancel from play restores pause, chat and mouse capture exactly")
    assert_eq(app.runner.active_game.blocker.mouse_filter, Control.MOUSE_FILTER_STOP, "cancel restores generated GUI input")

    app.chat_input.text = "Keep my text"
    app._capture_annotation()
    for i in 60:
        await process_frame
        if app.annotation_editor.visible: break
    var canvas = app.annotation_editor.canvas
    var center: Vector2 = canvas.image_rect().get_center()
    # Exercise real GUI pen events, not only the canvas's model methods.
    var down_mark := InputEventMouseButton.new()
    down_mark.position = canvas.global_position + center
    down_mark.global_position = down_mark.position
    down_mark.button_index = MOUSE_BUTTON_LEFT
    down_mark.pressed = true
    Input.parse_input_event(down_mark)
    await process_frame
    var up_mark = down_mark.duplicate()
    up_mark.pressed = false
    Input.parse_input_event(up_mark)
    await process_frame
    assert_true(not canvas.strokes.is_empty(), "real mouse input draws a pen stroke in the frozen picture")
    var attach_button = _find_button(app.annotation_editor, "Attach picture")
    attach_button.pressed.emit()
    assert_true(app.draft_pictures.size() == 1 and app.chat_overlay.visible and paused, "Attach queues a marked picture and returns to paused chat")
    assert_true(app.chat_input.text == "Keep my text", "capture preserves a previously composed message")
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("user://annotation-chat.png")
    if not app.draft_pictures.is_empty():
        var png: Image = app.picture_store.picture_image(app.draft_pictures[0].id)
        var marked_pixel := png.get_pixel(png.get_width() / 2, png.get_height() / 2)
        assert_true(marked_pixel.r > 0.8, "saved attachment includes the user's actual mouse-drawn mark")
    app._capture_annotation()
    for i in 60:
        await process_frame
        if app.annotation_editor.visible: break
    app._cancel_annotation()
    assert_true(app.chat_overlay.visible and paused and app.draft_pictures.size() == 1, "cancel an additional capture keeps chat and existing queued pictures")

    # Regression: returning from a generated game must leave New Game as host-canvas
    # UI, not a modal Window that can own focus invisibly and make the main window
    # appear frozen.
    app._set_chat_visible(false)
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
