extends SceneTree

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var runner = preload("res://src/core/game_runner.gd").new()
    root.add_child(runner)
    var tools = preload("res://src/core/game_tools.gd").new("user://wall-response", runner)
    tools.write_file("main.gd", "extends Node2D\nfunc _ready():\n    for i in range(64):\n        var body = StaticBody2D.new()\n        add_child(body)\n        var wall = Polygon2D.new()\n        wall.color = Color(0.09, 0.11, 0.17)\n        body.add_child(wall)\n")
    if not tools.reload_game().ok:
        quit(1)
        return
    var result = tools.execute("inspect_runtime", {"class": "Polygon2D", "depth": 2, "properties": ["color"]})
    var file = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
    file.store_string(JSON.stringify(result))
    file.close()
    runner.queue_free()
    await process_frame
    quit(0)
