extends SceneTree

var failures := 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if value:
        print("PASS: " + message)
    else:
        failures += 1
        push_error(message)

func run() -> void:
    root.size = Vector2i(1024, 640)
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    for frame in range(5):
        await process_frame
    var settings: Button
    for node in app.library_layer.find_children("*", "Button", true, false):
        if node.text == "Settings":
            settings = node
    check(settings != null, "library offers Settings")
    app.library_layer.move_to_front()
    var point = settings.get_global_rect().get_center()
    var motion = InputEventMouseMotion.new()
    motion.position = point
    root.push_input(motion)
    for pressed in [true, false]:
        var event = InputEventMouseButton.new()
        event.position = point
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        root.push_input(event)
        await process_frame
    check(app.settings_dialog.visible, "clicking library Settings opens the dialog")
    check(app.settings_dialog.get_index() > app.library_layer.get_index(), "Settings opens above the main menu")
    app._close_settings()
    var created = app.store.create_game("Library deletion fixture")
    app.library_search.text = created.name
    app._refresh_library()
    await process_frame
    var menu: MenuButton
    for node in app.library_layer.find_children("*", "MenuButton", true, false):
        menu = node
    check(menu != null and menu.get_popup().get_item_text(2).begins_with("Delete game"), "game card offers Delete game")
    menu.get_popup().id_pressed.emit(2)
    check(app.delete_dialog.visible and app.pending_delete == created.name, "Delete asks for confirmation for the selected game")
    app._delete_game_confirmed()
    check(not DirAccess.dir_exists_absolute(app.store.game_path(created.name)), "confirmed deletion removes the selected game")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
