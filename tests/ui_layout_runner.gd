extends SceneTree

# Exercise real view layout/navigation. Optional screenshots use isolated fixtures;
# never launch generated code or contact a model.
const Store = preload("res://src/core/workspace_store.gd")
var passed = 0
var failures = 0
var capture_dir = ""

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if value:
        passed += 1
        print("PASS: ", message)
    else:
        failures += 1
        push_error("FAIL: " + message)

func settle() -> void:
    for i in 5:
        await process_frame

func capture(name: String) -> void:
    await settle()
    if capture_dir != "":
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func inside(control: Control) -> bool:
    return Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect())

func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--captures="):
            capture_dir = arg.trim_prefix("--captures=")
            DirAccess.make_dir_recursive_absolute(capture_dir)
    root.size = Vector2i(1280, 720)
    var store = Store.new()
    store.ensure()
    var names = ["Neon Asteroids", "Space Bunny", "Forest After Dark", "A Very Long Workspace Name That Should Never Break The Gallery Layout"]
    for game in names:
        store.create_game(game)
    var total_games = store.list_games().size()
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await settle()
    var grid = app.library_layer.find_child("GamesList", true, false)
    check(grid.get_child_count() == total_games, "gallery displays all workspaces")
    check(grid.columns == 2, "wide gallery uses two columns")
    await capture("library")
    app.library_search.text = "BUNNY"
    app.library_search.text_changed.emit(app.library_search.text)
    await settle()
    check(grid.get_child_count() == 1, "search filters workspace names case insensitively")
    app.library_search.text = "missing"
    app.library_search.text_changed.emit(app.library_search.text)
    await settle()
    check(grid.get_child_count() == 1, "empty search has an actionable empty state")
    app.library_search.text = ""
    app.library_search.text_changed.emit(app.library_search.text)
    await settle()
    check(grid.get_child_count() == total_games and grid.columns == 2, "clearing search restores the gallery and columns")
    app._open_game(names[0])
    await settle()
    app.transcript_view.clear()
    app._append_chat("user", "Let’s make an arcade space game. Fast ships, neon trails, and one more try.")
    app._append_chat("assistant", "I’ll start with responsive movement, a field of asteroids, and a score that rewards close calls. We can tune the feel together after your first run.")
    await settle()
    check(app.workspace_title_label.text == names[0], "chat identifies the open workspace")
    check(not app.runner.has_active_game() and app.chat_overlay.visible, "redesigned workspace still opens safely in chat")
    check(app.run_game_button.disabled, "empty workspace cannot run")
    check(app.resume_game_button.disabled, "workspace cannot resume before a game is running")
    check(inside(app.send_button) and inside(app.chat_input), "chat composer stays inside the viewport")
    await capture("workspace")
    app._reload_approval_changed(true)
    await settle()
    check(inside(app.approve_reload_button), "reload approval fits without displacing the composer")
    await capture("reload-request")
    app._reload_approval_changed(false)
    app._open_settings()
    await settle()
    var tabs = app.settings_dialog.find_child("SettingsTabs", true, false)
    check(tabs.get_tab_count() == 4, "settings groups model, agent, conversation and game preferences")
    await capture("settings")
    tabs.current_tab = 2
    await settle()
    check(app.compact_now_button.is_visible_in_tree(), "conversation tools are reachable on their settings tab")
    var escape = InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    app._input(escape)
    check(not app.settings_dialog.visible and app.chat_overlay.visible, "Escape closes settings before closing chat")
    root.size = Vector2i(1024, 640)
    await settle()
    check(inside(app.send_button) and inside(app.chat_input), "composer remains usable at minimum window size")
    app._open_settings()
    await settle()
    check(inside(tabs), "settings fit at minimum window size")
    await capture("settings-small")
    app._close_settings()
    app._return_to_library()
    await settle()
    check(grid.columns == 1, "smaller library switches to one column")
    app._open_new_game()
    await settle()
    check(inside(app.name_edit), "new game dialog fits at minimum window size")
    app._input(escape)
    check(not app.new_game_dialog.visible, "Escape dismisses new game dialog")
    app._open_rename(names[0])
    await settle()
    check(app.rename_dialog.get_parent() == app.host_ui_root and inside(app.rename_edit), "rename uses the host overlay and fits at minimum size")
    app._input(escape)
    check(not app.rename_dialog.visible, "Escape dismisses rename without changing the game")
    app._ask_delete(names[0])
    await settle()
    check(app.delete_dialog.get_parent() == app.host_ui_root and inside(app.delete_game_label), "destructive confirmation clearly identifies the game in the host overlay")
    app._input(escape)
    check(not app.delete_dialog.visible and names[0] in store.list_games(), "Escape cancels deletion and preserves the game")
    root.size = Vector2i(1280, 720)
    app._open_new_game()
    await capture("new-game")
    app.queue_free()
    paused = false
    await process_frame
    for game in names:
        store.delete_game(game)
    print("UI LAYOUT TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)
