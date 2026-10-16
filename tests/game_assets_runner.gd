extends SceneTree

var failures := 0
var passed := 0

func check(condition: bool, message: String) -> void:
    if condition:
        passed += 1
        print("PASS: ", message)
    else:
        failures += 1
        push_error("FAIL: " + message)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var workspace = "user://games/Portable assets"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace.path_join("nested")))
    var png = Image.create(3, 2, false, Image.FORMAT_RGBA8)
    png.fill(Color.CORNFLOWER_BLUE)
    png.save_png(workspace.path_join("player.png"))
    JsonStore.write_bytes_atomic(workspace.path_join("asset.txt"), "portable".to_utf8_buffer())
    JsonStore.write_bytes_atomic(workspace.path_join("nested/helper.gd"), """extends Node
var contents = ""
func _ready():
    var node = self
    while node != null and not node.has_meta("gamesmith_assets"):
        node = node.get_parent()
    if node == null:
        push_error("No GameSmith asset helper")
        return
    var assets = node.get_meta("gamesmith_assets")
    contents = FileAccess.get_file_as_string(assets.path("asset.txt"))
""".to_utf8_buffer())
    JsonStore.write_bytes_atomic(workspace.path_join("main.gd"), """extends Node
var texture: ImageTexture
func _ready():
    var assets = get_meta("gamesmith_assets")
    var image = Image.load_from_file(assets.path("player.png"))
    if image == null:
        push_error("Missing workspace PNG")
        return
    texture = ImageTexture.create_from_image(image)
    var child = preload("nested/helper.gd").new()
    child.name = "Helper"
    add_child(child)
""".to_utf8_buffer())
    var runner = GameRunner.new()
    root.add_child(runner)
    for attempt in range(2):
        var loaded = runner.load_game(workspace)
        check(loaded.ok, "Asset helper exists before nested _ready on load %d" % attempt)
        if loaded.ok:
            check(runner.active_game.get_node("Helper").contents == "portable", "Nested script reads portable workspace asset")
            check(runner.active_game.texture != null and runner.active_game.texture.get_size() == Vector2(3, 2), "Documented PNG loading creates a texture without editor imports")
            var assets = runner.active_game.get_meta("gamesmith_assets")
            check(assets.path("../outside") == "" and assets.path("res://asset.txt") == "", "Asset helper rejects non-relative paths")
    runner.unload_game()
    var renamed = workspace + " renamed"
    check(DirAccess.rename_absolute(ProjectSettings.globalize_path(workspace), ProjectSettings.globalize_path(renamed)) == OK, "Fixture workspace renames")
    var loaded = runner.load_game(renamed)
    check(loaded.ok and runner.active_game.get_node("Helper").contents == "portable", "Reopened renamed game resolves its new workspace")
    var supervisor = preload("res://src/core/test_game_supervisor.gd").new()
    root.add_child(supervisor)
    var started = supervisor.start(renamed, "headless")
    var deadline = Time.get_ticks_msec() + 15000
    var state: Dictionary = {}
    while Time.get_ticks_msec() < deadline:
        state = supervisor.status(started.run_id)
        if state.get("state") in ["running", "exited"]: break
        await create_timer(0.05).timeout
    check(state.get("load_result", {}).get("ok", false), "Separate headless process receives the same asset helper")
    supervisor.request_stop(started.run_id)
    while Time.get_ticks_msec() < deadline and supervisor.status(started.run_id).get("state") != "exited":
        await create_timer(0.05).timeout
    JsonStore.write_bytes_atomic(renamed.path_join("main.gd"), "extends Node\nfunc _ready():\n\tget_meta('gamesmith_assets').load_glb('missing.glb')\n".to_utf8_buffer())
    var rejected = runner.load_game(renamed)
    check(not rejected.ok and runner.active_game.get_node("Helper").contents == "portable", "Missing GLB rejects startup while preserving the working game")
    supervisor.queue_free()
    runner.queue_free()
    await process_frame
    print("GAME ASSETS: %d passed, %d failed" % [passed, failures])
    quit(1 if failures else 0)
