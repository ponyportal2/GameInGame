extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
const Tools = preload("res://src/core/game_tools.gd")
var failed := 0
var passed := 0

func _init() -> void:
    call_deferred("run")

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS: " + label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func run() -> void:
    var runner = Runner.new()
    root.add_child(runner)
    var tools = Tools.new("user://runtime-properties", runner)
    check(not tools.execute("inspect_runtime", {}).get("ok", false), "no active game is rejected")
    tools.write_file("enemy.gd", "extends Node2D\nvar speed: float = 80.0\nvar health: int = 43\nvar title: String = 'enemy'\nvar enabled: bool = true\nvar tint: Color = Color.WHITE\nvar limited: float = 0.0:\n    set(value): limited = minf(value, 10.0)\nvar vanish: bool = false:\n    set(value):\n        vanish = value\n        if value: queue_free()\n")
    tools.write_file("main.gd", "extends Node2D\nconst Enemy = preload('enemy.gd')\nfunc _ready():\n    for i in range(50):\n        var enemy = Enemy.new()\n        enemy.name = 'Enemy%d' % i\n        add_child(enemy)\n        enemy.add_to_group('enemies')\n")
    tools.patch_file("enemy.gd", "var speed: float = 80.0", "var speed = 80.0")
    tools.write_file("getter.gd", "extends Node\nvar dangerous: float:\n    get:\n        queue_free()\n        return 1.0\n")
    check(tools.reload_game().ok, "fixture loaded through production loader")
    var game = runner.active_game
    var inspected = tools.execute("inspect_runtime", {"group": "enemies", "properties": ["speed", "health"], "limit": 100})
    check(inspected.get("ok", false) and inspected.get("nodes", []).size() == 50, "inspect selects fifty live enemies")
    if not inspected.get("ok", false) or inspected.get("nodes", []).size() != 50:
        runner.queue_free()
        quit(1)
        return
    var handles: Array = inspected.nodes.map(func(node): return node.handle)
    var result = tools.execute("set_properties", {"targets": handles, "values": {"speed": 120.0}})
    check(result.get("ok", false) and result.get("changed", 0) == 50 and result.get("failed", -1) == 0, "batch changes fifty enemies")
    check(runner.active_game == game and game.get_node("Enemy0").speed == 120.0 and game.get_node("Enemy0").health == 43, "game and unrelated state survive")
    check(str(game.get_node("Enemy0").get_instance_id()) == handles[0].instance_id, "node identity survives")
    var handle = handles[0]
    result = tools.execute("set_properties", {"targets": [handle], "values": {"limited": 50.0}})
    check(result.get("ok", false) and result.results[0].values.limited == 10.0, "setter readback reports actual clamped value")
    result = tools.execute("set_properties", {"targets": [handle], "values": {"position": {"type": "Vector2", "x": 12.0, "y": 34.0}, "tint": {"type": "Color", "r": 0.2, "g": 0.3, "b": 0.4, "a": 1.0}}})
    check(result.get("ok", false) and game.get_node("Enemy0").position == Vector2(12, 34), "typed vector and color writes")
    var spatial = Node3D.new()
    spatial.name = "Spatial"
    game.add_child(spatial)
    var spatial_handle = tools.execute("inspect_runtime", {"root": "Spatial"}).nodes[0].handle
    result = tools.execute("set_properties", {"targets": [spatial_handle], "values": {"position": {"type": "Vector3", "x": 1, "y": 2, "z": 3}}})
    check(result.ok and spatial.position == Vector3(1, 2, 3), "3D property mutation")
    for value in [{"type": "Vector3", "x": 1, "y": 2}, {"type": "Vector3", "x": 1, "y": 2, "z": "3"}, {"type": "Vector3", "x": 1, "y": 2, "z": 3, "extra": 4}]:
        check(not tools.execute("set_properties", {"targets": [spatial_handle], "values": {"position": value}}).ok, "malformed tagged value rejected")
    result = tools.execute("set_properties", {"targets": [spatial_handle], "values": {"name": "RenamedSpatial"}})
    check(result.ok and spatial.name == &"RenamedSpatial" and result.results[0].handle.path == "RenamedSpatial", "StringName write returns refreshed path handle")
    check(not tools.execute("set_properties", {"targets": [spatial_handle], "values": {"visible": false}}).ok, "rename invalidates old path handle")
    result = tools.execute("set_properties", {"targets": [handle], "values": {"health": 37, "enabled": false, "title": "swift"}})
    check(result.ok and result.results[0].values == {"health": 37, "enabled": false, "title": "swift"}, "integer boolean and string writes round trip")
    result = tools.execute("inspect_runtime", {"root": "Enemy0", "depth": 0, "properties": ["position", "tint", "missing", "script"]})
    check(result.ok and result.nodes[0].values.position == {"type": "Vector2", "x": 12.0, "y": 34.0} and result.nodes[0].property_errors.has("script") and result.nodes[0].property_errors.has("missing"), "typed readback and unsupported property errors")
    for path in ["..", "../..", "/root", "Enemy0:script"]:
        check(not tools.execute("inspect_runtime", {"root": path}).get("ok", false), "inspection rejects escaped path " + path)
    var forged = handle.duplicate()
    forged.path = "../.."
    check(not tools.execute("set_properties", {"targets": [forged], "values": {"name": "owned"}}).ok, "mutation rejects host escape")
    forged = handle.duplicate()
    forged.instance_id = str(game.get_instance_id())
    check(not tools.execute("set_properties", {"targets": [forged], "values": {"speed": 1}}).ok, "identity mismatch rejected")
    forged = handle.duplicate()
    forged.game_generation = "older-game"
    check(not tools.execute("set_properties", {"targets": [forged], "values": {"speed": 1}}).ok, "generation mismatch rejected")
    for values in [{"speed": "fast"}, {"health": 1.5}, {"missing": 3}, {"script": null}, {"speed": {"type": "Vector2", "x": 1, "y": 2}}]:
        result = tools.execute("set_properties", {"targets": [handle], "values": values})
        check(not result.ok and game.get_node("Enemy0").speed == 120.0, "invalid write rejected " + str(values))
    result = tools.execute("set_properties", {"targets": [handle], "values": {"speed": 999.0, "missing": 2}})
    check(not result.ok and game.get_node("Enemy0").speed == 120.0, "all target properties validated before writing")
    result = tools.execute("inspect_runtime", {"limit": 3})
    check(result.ok and result.nodes.size() == 3 and result.truncated, "wide inspection bounded")
    check(tools.execute("inspect_runtime", {"depth": 0}).nodes.size() == 1, "depth zero inspects root only")
    check(tools.execute("inspect_runtime", {"class": "Node2D", "group": "enemies"}).nodes.size() == 50, "class and group filters combine")
    check(tools.execute("inspect_runtime", {"script": tools.workspace.path_join("enemy.gd")}).nodes.size() == 50, "script filter")
    var parent = Node.new()
    parent.name = "QueuedParent"
    game.add_child(parent)
    var child = Node2D.new()
    child.name = "Child"
    parent.add_child(child)
    var child_handle = tools.execute("inspect_runtime", {"root": "QueuedParent/Child"}).nodes[0].handle
    parent.queue_free()
    check(not tools.execute("set_properties", {"targets": [child_handle], "values": {"position": {"type": "Vector2", "x": 1, "y": 2}}}).ok, "queued ancestor invalidates child handle")
    for args in [{"targets": [], "values": {"speed": 1}}, {"targets": [handle], "values": {}}, {"targets": [handle, handle], "values": {"speed": 1}}, {"targets": ["Enemy0"], "values": {"speed": 1}}]:
        check(not tools.execute("set_properties", args).ok, "malformed or duplicate batch rejected")
    var stale = handles[1]
    game.get_node("Enemy1").free()
    var replacement = Node2D.new()
    replacement.name = "Enemy1"
    game.add_child(replacement)
    result = tools.execute("set_properties", {"targets": [stale, handle], "values": {"speed": 130.0}})
    check(not result.ok and result.changed == 1 and result.failed == 1 and game.get_node("Enemy0").speed == 130.0, "partial batch reports stale target and successful target")
    result = tools.execute("set_properties", {"targets": [handle], "values": {"vanish": true, "speed": 999.0}})
    check(not result.ok and result.failed == 1, "setter queuing node for deletion stops subsequent writes")
    await process_frame
    check(tools.reload_game().ok, "reload fallback still works")
    check(not tools.execute("set_properties", {"targets": [handles[2]], "values": {"speed": 1}}).ok, "reload invalidates handles")
    check(runner.active_game.get_node("Enemy2").speed == 80.0, "live patch does not modify source")
    var dangerous = load(tools.workspace.path_join("getter.gd")).new()
    dangerous.name = "Dangerous"
    runner.active_game.add_child(dangerous)
    check(not tools.execute("inspect_runtime", {"root": "Dangerous", "properties": ["dangerous"]}).ok, "getter invalidation returns an honest failure")
    var prompt = preload("res://src/pi/pi_runtime_config.gd")._game_prompt()
    check("inspect_runtime" in prompt and "set_properties" in prompt and "parameter patch" in prompt, "shared prompt teaches live parameter iteration")
    var bridge = "user://runtime-properties/bridge"
    DirAccess.make_dir_recursive_absolute(bridge)
    for harness in preload("res://src/agent/harness_inventory.gd").all():
        var controller = load("res://" + harness.controller).new()
        root.add_child(controller)
        controller.tools = tools
        controller._dispatch_host_request({"id": "inspect", "command": "inspect_runtime", "args": {"root": "Enemy2", "properties": ["speed"]}}, bridge)
        var response = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-inspect.json")))
        check(response is Dictionary and response.get("ok", false), harness.id + " host bridge inspects live game")
        if response is Dictionary and response.get("ok", false):
            controller._dispatch_host_request({"id": "set", "command": "set_properties", "args": {"targets": [response.nodes[0].handle], "values": {"speed": 140.0}}}, bridge)
            var patched = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-set.json")))
            check(patched is Dictionary and patched.get("ok", false) and runner.active_game.get_node("Enemy2").speed == 140.0, harness.id + " host bridge mutates live game")
        controller.queue_free()
    for invalid in [{"limit": 101}, {"limit": "many"}, {"depth": -1}, {"depth": 0.5}, {"properties": [1]}, {"group": []}]:
        check(not tools.execute("inspect_runtime", invalid).ok, "malformed inspection rejected")
    var current = tools.execute("inspect_runtime", {"root": "Enemy2"}).nodes[0].handle
    for values in [{"speed": INF}, {"speed": NAN}, {"health": 9007199254740992}, {"title": "a".repeat(1025)}, {"speed": []}, {"speed": null}]:
        check(not tools.execute("set_properties", {"targets": [current], "values": values}).ok, "oversized or unsupported value rejected")
    var wide = Node.new()
    wide.name = "Wide"
    runner.active_game.add_child(wide)
    for index in range(1100): wide.add_child(Node.new())
    result = tools.execute("inspect_runtime", {"root": "Wide", "group": "absent"})
    check(result.ok and result.visited <= 1000 and result.truncated and result.nodes.is_empty(), "filtered wide traversal still bounded")
    var original_script = runner.active_game.get_node("Enemy2").get_script()
    tools.patch_file("enemy.gd", "var speed = 80.0", "var speed = 160.0")
    var future_enemy = original_script.new()
    check(future_enemy.speed == 80.0, "source edits do not hot-reload future instances of loaded scripts")
    future_enemy.free()
    check(tools.reload_game().ok and runner.active_game.get_node("Enemy2").speed == 160.0, "reload applies persistent source edits")
    runner.unload_game()
    check(not tools.execute("set_properties", {"targets": [handles[2]], "values": {"speed": 1}}).ok, "unload invalidates handles")
    runner.queue_free()
    await process_frame
    print("Runtime properties: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)
