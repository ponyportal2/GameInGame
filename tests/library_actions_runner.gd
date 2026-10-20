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
    for frame in range(5):
        await process_frame
    point = menu.get_global_rect().get_center()
    motion.position = point
    root.push_input(motion)
    for pressed in [true, false]:
        var event = InputEventMouseButton.new()
        event.position = point
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        root.push_input(event)
        await process_frame
    check(menu.get_popup().visible, "mouse click opens the game actions popup")
    check(app.host_ui_canvas.layer < 1024, "embedded menu windows render above the host UI")
    if OS.get_environment("GAMESMITH_MENU_CAPTURE") != "":
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(OS.get_environment("GAMESMITH_MENU_CAPTURE"))
    menu.get_popup().hide()
    menu.get_popup().id_pressed.emit(2)
    check(app.delete_dialog.visible and app.pending_delete == created.name, "Delete asks for confirmation for the selected game")
    app._delete_game_confirmed()
    check(not DirAccess.dir_exists_absolute(app.store.game_path(created.name)), "confirmed deletion removes the selected game")
    # Deleting the game that is currently open must retire the adapter first:
    # Windows will not remove a directory a live process holds as its cwd.
    OS.set_environment("GAMESMITH_OPENCODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-opencode.mjs"))
    app.name_edit.text = "Open game deletion fixture"
    app.harness_option.select(2)
    app._create_game()
    var open_name: String = app.current_game
    check(open_name == "Open game deletion fixture", "the open deletion fixture is created and opened")
    app.agent.send_player_request("hello")
    var idle_deadline = Time.get_ticks_msec() + 20000
    while app.agent.busy and Time.get_ticks_msec() < idle_deadline:
        await process_frame
    check(is_instance_valid(app.agent.rpc) and app.agent.rpc.running, "the open game keeps a live adapter before deletion")
    app.pending_delete = open_name
    app._delete_game_confirmed()
    check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(app.store.game_path(open_name))), "deleting the open game removes its workspace")
    check(not app.store.list_games().has(open_name), "deleting the open game removes it from the library")
    check(app.current_game == "", "deleting the open game returns to the library")
    # Renaming the open game moves its files; the runner must follow, otherwise
    # snapshot promotion stops recognising the live workspace after the rename.
    var rename_created = app.store.create_game("Rename source fixture")
    var rename_path: String = app.store.game_path(rename_created.name)
    var handle = FileAccess.open(rename_path.path_join("main.gd"), FileAccess.WRITE)
    handle.store_string("extends Node3D\n")
    handle.close()
    app._open_game(rename_created.name)
    await process_frame
    app._run_game()
    await process_frame
    check(app.runner.active_source_path == rename_path.path_join("main.gd"), "the running game records its loaded source")
    app._open_rename(rename_created.name)
    app.rename_edit.text = "Rename source fixture renamed"
    app._rename_game()
    await process_frame
    var renamed_path: String = app.store.game_path("Rename source fixture renamed")
    check(app.current_game == "Rename source fixture renamed", "renaming the open game updates the title")
    check(app.runner.active_source_path == renamed_path.path_join("main.gd"), "renaming the open game rebinds the loaded source")
    app.pending_delete = "Rename source fixture renamed"
    app._delete_game_confirmed()
    check(not DirAccess.dir_exists_absolute(renamed_path), "the renamed fixture is cleaned up")
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
