extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value: failures += 1
func run() -> void:
    var first = load("res://main.tscn").instantiate()
    root.add_child(first)
    await process_frame
    first.name_edit.text = "Ownership fixture"
    first._create_game()
    var name = first.current_game
    var second = load("res://main.tscn").instantiate()
    root.add_child(second)
    await process_frame
    second._open_game(name)
    for choice in [1, 2, 0]:
        first._open_settings()
        first.game_harness_option.select(choice)
        first._save_settings()
        check(not second.game_edit_guard.acquire(), "ownership survives harness switch " + str(choice))
    first.agent.busy = true
    first.agent.cancel()
    check(not second.game_edit_guard.acquire(), "Stop does not release ownership")
    for harness in ["pi", "command-code", "opencode", "codex"]:
        second.agent.free()
        var script = {"pi":"pi", "command-code":"command_code", "opencode":"opencode", "codex":"codex"}[harness]
        second.agent = load("res://src/agent/" + script + "_agent_controller.gd").new()
        second.add_child(second.agent)
        second.agent.configure(name, second.tools)
        second.agent.send_player_request("Must not start")
        check(not second.agent.busy and second.agent.rpc == null, "second writer rejected for " + harness)
        check("another GameSmith" in second.agent.last_error, "ownership rejection explains " + harness)
    second._open_settings()
    second.game_harness_option.select(2)
    second._save_settings()
    check(second.metadata.read_game(name).get("harness", "pi") == "pi", "other window cannot switch harness")
    second.rename_target = name
    second.rename_edit.text = "Stolen name"
    second._rename_game()
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(second.store.game_path(name))), "other window cannot rename")
    second.pending_delete = name
    second._delete_game_confirmed()
    check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(second.store.game_path(name))), "other window cannot delete")
    first.rename_target = name
    first.rename_edit.text = "Renamed ownership fixture"
    first._rename_game()
    check(first.current_game == "Renamed ownership fixture", "owner can rename its game")
    second._show_library()
    second._open_game(first.current_game)
    check(not second.game_edit_guard.acquire(), "rename transfers ownership to the new game path")
    first._show_library()
    check(second.agent.acquire_editor(), "ownership becomes available when first window closes")
    second.agent.cancel()
    first.queue_free()
    second.queue_free()
    await process_frame
    quit(1 if failures else 0)
