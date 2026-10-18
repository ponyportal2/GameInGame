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
    var outcomes = []
    var handles = result.nodes.map(func(entry): return entry.handle)
    # A real partial batch, including a stale identity rather than fabricated IDs.
    runner.active_game.get_node(handles[7].path).free()
    outcomes.append(tools.execute("set_properties", {"targets": handles.slice(0, 50), "values": {"color": {"type": "Color", "r": 0.3, "g": 0.4, "b": 0.5, "a": 1}}}))
    tools.write_file("edge.gd", "extends Node\nvar first = 0\nvar giant = 0:\n    get: return '\\n'.repeat(1024) if first == 1 else 0\n    set(value): giant = value\nvar rename = false:\n    set(value):\n        rename = value\n        name = 'x'.repeat(1024)\nvar vanish = false:\n    set(value):\n        vanish = value\n        queue_free()\nvar text: String = 'original':\n    set(value): text = '\\n'.repeat(1024)\nvar escaped: String = 'original':\n    set(value): escaped = String.chr(1).repeat(1024)\nvar unicode: String = 'original':\n    set(value): unicode = String.chr(128161).repeat(1024)\n")
    for mode in ["giant", "rename", "vanish", "text", "escaped", "unicode"]:
        var node = load(tools.workspace.path_join("edge.gd")).new()
        node.name = mode
        runner.active_game.add_child(node)
        var handle = tools.execute("inspect_runtime", {"root": mode}).nodes[0].handle
        var values = {"first": 1}
        values[mode] = "requested" if mode in ["text", "escaped", "unicode"] else (1 if mode == "giant" else true)
        outcomes.append(tools.execute("set_properties", {"targets": [handle], "values": values}))
    file = FileAccess.open(OS.get_cmdline_user_args()[0] + ".mutations.json", FileAccess.WRITE)
    file.store_string(preload("res://src/core/json_output.gd").stringify(outcomes))
    file.close()
    runner.queue_free()
    await process_frame
    quit(0)
