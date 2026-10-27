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
    tools.write_file("enemy.gd", "extends Node2D\nvar speed: float = 80.0\nvar health: int = 43\nvar title: String = 'enemy'\nvar enabled: bool = true\nvar tint: Color = Color.WHITE\n@export_group('Behavior')\n@export_subgroup('Tuning')\n@export var aggression: float = 1.0\nvar limited: float = 0.0:\n    set(value): limited = minf(value, 10.0)\nvar vanish: bool = false:\n    set(value):\n        vanish = value\n        if value: queue_free()\n")
    tools.write_file("main.gd", "extends Node2D\nconst Enemy = preload('enemy.gd')\nfunc _ready():\n    for i in range(50):\n        var enemy = Enemy.new()\n        enemy.name = 'Enemy%d' % i\n        add_child(enemy)\n        enemy.add_to_group('enemies')\n")
    tools.patch_file("enemy.gd", "var speed: float = 80.0", "var speed = 80.0")
    tools.write_file("getter.gd", "extends Node\nvar dangerous: float:\n    get:\n        queue_free()\n        return 1.0\n")
    var loaded = await tools.wait_reload(tools.reload_game())
    check(loaded.ok, "fixture loaded through production loader")
    if not loaded.ok or runner.active_game == null:
        runner.queue_free()
        quit(1)
        return
    var game = runner.active_game
    var budget_handles = tools.execute("inspect_runtime", {"group": "enemies", "properties": ["title"]}).nodes.map(func(entry): return entry.handle)
    var rejected_batch = tools.execute("set_properties", {"targets": budget_handles, "values": {"title": "new"}})
    check(not rejected_batch.ok and rejected_batch.get("writes_started", true) == false and "Split" in rejected_batch.get("error", ""), "oversized possible string readback rejected before writes")
    check(game.get_node("Enemy0").title == "enemy" and game.get_node("Enemy49").title == "enemy", "budget rejection leaves every target untouched")
    var line_rejected = tools.execute("set_properties", {"targets": budget_handles.slice(0, 3), "values": {"title": "small"}})
    check(not line_rejected.ok and not line_rejected.get("writes_started", true) and game.get_node("Enemy0").title == "enemy", "logical-line reservation rejects even a small requested string before writes")
    var extra_handle = budget_handles[0].duplicate()
    extra_handle.extra = "x".repeat(100000)
    check(not tools.execute("set_properties", {"targets": [extra_handle], "values": {"title": "ignored"}}).ok and game.get_node("Enemy0").title == "enemy", "handle metadata cannot amplify mutation results")
    var long_handles = []
    var long_nodes = []
    for index in range(30):
        var node = Node2D.new()
        node.name = "界".repeat(600) + str(index)
        game.add_child(node)
        long_nodes.append(node)
        long_handles.append(tools.execute("inspect_runtime", {"root": str(node.name)}).nodes[0].handle)
    var byte_rejected = tools.execute("set_properties", {"targets": long_handles, "values": {"visible": false}})
    check(not byte_rejected.ok and not byte_rejected.get("writes_started", true), "UTF-8 handle bytes reject a batch independently of line count")
    check(long_nodes.all(func(node): return node.visible), "byte-budget rejection leaves all targets untouched")
    for node in long_nodes: node.free()
    var wrong_path = tools.execute("inspect_runtime", {"path": "Enemy0", "discover_properties": true})
    check(not wrong_path.ok and "root" in wrong_path.get("error", "") and "path" in wrong_path.get("error", ""), "unknown path argument rejected with root guidance instead of inspecting game root")
    check(not tools.execute("inspect_runtime", {"root": "Enemy0", "typo": true}).ok, "unknown inspection arguments rejected even with valid root")
    var empty_discovery = tools.execute("inspect_runtime", {"class": "Node2D", "group": "enemies", "discover_properties": true})
    check(empty_discovery.ok and empty_discovery.nodes.is_empty() and "depth_limit" in empty_discovery.truncated_by and "depth" in empty_discovery.get("recovery", "") and "root" in empty_discovery.get("recovery", ""), "zero-match discovery explains incomplete depth-limited search")
    var absent = tools.execute("inspect_runtime", {"group": "nonexistent"})
    check(absent.ok and absent.nodes.is_empty() and not absent.has("recovery"), "complete zero-match inspection does not suggest depth recovery")
    var garden = Node3D.new()
    garden.name = "Garden"
    game.add_child(garden)
    var model_root = Node3D.new()
    model_root.name = "GardenModel"
    garden.add_child(model_root)
    var model = Node3D.new()
    model.name = "model"
    model_root.add_child(model)
    var cliff = MeshInstance3D.new()
    cliff.name = "Cliff"
    model.add_child(cliff)
    var deep_search = tools.execute("inspect_runtime", {"class": "MeshInstance3D"})
    check(deep_search.nodes.is_empty() and "depth_limit" in deep_search.truncated_by and deep_search.has("recovery"), "Tetriscat imported mesh beyond default depth reports incomplete search")
    var exact_mesh = tools.execute("inspect_runtime", {"root": "Garden/GardenModel/model/Cliff", "discover_properties": true, "properties": ["visible"]})
    check(exact_mesh.ok and exact_mesh.nodes.size() == 1 and exact_mesh.nodes[0].class == "MeshInstance3D" and exact_mesh.nodes[0].handle.path == "Garden/GardenModel/model/Cliff", "root targets actual imported mesh for discovery")
    var hide_mesh = tools.execute("set_properties", {"targets": [exact_mesh.nodes[0].handle], "values": {"visible": false}})
    check(hide_mesh.ok and hide_mesh.changed == 1 and not cliff.visible and runner.active_game == game, "focused discovery handle hides mesh without reload")
    garden.free()
    var inspected = tools.execute("inspect_runtime", {"group": "enemies", "properties": ["speed", "health"], "limit": 100})
    check(inspected.get("ok", false) and inspected.get("nodes", []).size() == 50, "inspect selects fifty live enemies")
    if not inspected.get("ok", false) or inspected.get("nodes", []).size() != 50:
        runner.queue_free()
        quit(1)
        return
    check(not inspected.nodes[0].has("available_properties") and not inspected.nodes[0].has("script"), "normal inspection omits discovery metadata")
    var discovery = tools.execute("inspect_runtime", {"root": "Enemy0", "discover_properties": true})
    check(discovery.ok and discovery.nodes.size() == 1, "discovery defaults to root only")
    check(discovery.nodes.size() == 1, "discovery default returns one node")
    var broad_discovery = tools.execute("inspect_runtime", {"discover_properties": true, "depth": 3})
    check(broad_discovery.ok and broad_discovery.nodes.size() == 1 and broad_discovery.has_more, "broad discovery defaults to one result")
    check(not tools.execute("inspect_runtime", {"discover_properties": true, "limit": 4}).ok, "discovery rejects more than three results")
    var names = discovery.nodes[0].get("available_properties", []).map(func(prop): return prop.name)
    check("speed" in names and "Transform" not in names and "Visibility" not in names and "Behavior" not in names and "Tuning" not in names and "aggression" in names, "discovery excludes category headings and retains untyped fields")
    check(not tools.execute("inspect_runtime", {"root": "Enemy0", "properties": ["Transform"]}).nodes[0].values.has("Transform"), "headings cannot be read as properties")
    var walls = Node2D.new()
    walls.name = "Walls"
    game.add_child(walls)
    for i in range(200):
        var body = StaticBody2D.new()
        body.name = "Wall%d" % i
        walls.add_child(body)
        var polygon = Polygon2D.new()
        polygon.color = Color(0.09, 0.11, 0.17)
        body.add_child(polygon)
    var wall_sample = tools.execute("inspect_runtime", {"root": "Walls", "class": "Polygon2D", "depth": 2, "limit": 64, "properties": ["color"]})
    var public_response = {"content": [{"type": "text", "text": JSON.stringify(wall_sample)}], "isError": false}
    check(JSON.stringify(public_response).to_utf8_buffer().size() < 24000, "64-wall serialized MCP response stays below 24KB")
    var wall_handles: Array = []
    var identities = {}
    var offset = 0
    for page_index in range(5):
        var page = tools.execute("inspect_runtime", {"root": "Walls", "class": "Polygon2D", "depth": 2, "limit": 50, "offset": offset, "properties": ["color"]})
        check(page.ok and page.nodes.size() == 50, "wall pagination returns fifty actual matches")
        for entry in page.nodes:
            identities[entry.handle.instance_id] = true
            wall_handles.append(entry.handle)
        if not page.get("has_more", false):
            check(page.get("next_offset") == null and not page.truncated, "last exact-size page has no false continuation")
            break
        check(page.get("next_offset") == offset + 50 and "result_limit" in page.get("truncated_by", []), "page continuation counts matching nodes")
        offset = page.next_offset
    check(wall_handles.size() == 200 and identities.size() == 200, "pagination discovers all 200 identities without guessing")
    var color_value = {"type": "Color", "r": 0.3, "g": 0.38, "b": 0.5, "a": 1.0}
    for start in range(0, wall_handles.size(), 50):
        var patch = tools.execute("set_properties", {"targets": wall_handles.slice(start, start + 50), "values": {"color": color_value}})
        check(patch.ok and patch.changed == 50 and patch.failed == 0 and patch.temporary, "wall recolor patches real handles in output-safe batches")
    check(runner.active_game == game and game.get_node("Enemy0").health == 43, "wall recolor preserves game and unrelated state")
    var recolored = tools.execute("inspect_runtime", {"root": "Walls", "class": "Polygon2D", "depth": 2, "limit": 100, "properties": ["color"]})
    check(recolored.nodes.all(func(entry): return is_equal_approx(entry.values.color.r, 0.3)), "wall recolor verified by fresh readback")
    var shallow = tools.execute("inspect_runtime", {"root": "Walls", "depth": 0})
    check("depth_limit" in shallow.get("truncated_by", []) and not shallow.get("has_more", true) and shallow.get("next_offset") == null, "depth cutoff is not pageable")
    var beyond = tools.execute("inspect_runtime", {"root": "Walls", "class": "Polygon2D", "depth": 2, "offset": 200})
    check(beyond.nodes.is_empty() and not beyond.get("has_more", true), "offset beyond matches returns empty final page")
    var combined = tools.execute("inspect_runtime", {"root": "Walls", "class": "StaticBody2D", "depth": 1, "limit": 1})
    check("result_limit" in combined.get("truncated_by", []) and "depth_limit" in combined.get("truncated_by", []), "result and depth truncation reasons coexist")
    walls.free()
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
    check((await tools.wait_reload(tools.reload_game())).ok, "reload fallback still works")
    check(not tools.execute("set_properties", {"targets": [handles[2]], "values": {"speed": 1}}).ok, "reload invalidates handles")
    check(runner.active_game.get_node("Enemy2").speed == 80.0, "live patch does not modify source")
    var dangerous = load(tools.workspace.path_join("getter.gd")).new()
    dangerous.name = "Dangerous"
    runner.active_game.add_child(dangerous)
    check(not tools.execute("inspect_runtime", {"root": "Dangerous", "properties": ["dangerous"]}).ok, "getter invalidation returns an honest failure")
    var prompt = preload("res://src/pi/pi_runtime_config.gd")._game_prompt()
    check("inspect_runtime" in prompt and "set_properties" in prompt and "parameter patch" in prompt, "shared prompt teaches live parameter iteration")
    check("Never infer" in prompt and "live-only" in prompt and "do not reload" in prompt and "visual" in prompt, "prompt explains live-only precedence handles and evidence")
    check("Godot late-child lifecycle" in prompt and "request_ready()" in prompt and "process_physics_priority" in prompt and "ordinary startup alone" in prompt, "shared prompt explains measured late insertion lifecycle and integration checks")
    var bridge = "user://runtime-properties/bridge"
    DirAccess.make_dir_recursive_absolute(bridge)
    for harness in preload("res://src/agent/harness_inventory.gd").all():
        var controller = load("res://" + harness.controller).new()
        root.add_child(controller)
        controller.tools = tools
        controller._dispatch_host_request({"id": "bad-inspect", "command": "inspect_runtime", "args": {"path": "Enemy2"}}, bridge)
        var rejected = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-bad-inspect.json")))
        check(rejected is Dictionary and not rejected.get("ok", true) and "root" in rejected.get("error", ""), harness.id + " host bridge rejects ignored path argument")
        controller._dispatch_host_request({"id": "inspect", "command": "inspect_runtime", "args": {"root": "Enemy2", "properties": ["speed"]}}, bridge)
        var response = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-inspect.json")))
        check(response is Dictionary and response.get("ok", false), harness.id + " host bridge inspects live game")
        if response is Dictionary and response.get("ok", false):
            controller._dispatch_host_request({"id": "set", "command": "set_properties", "args": {"targets": [response.nodes[0].handle], "values": {"speed": 140.0}}}, bridge)
            var patched = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-set.json")))
            check(patched is Dictionary and patched.get("ok", false) and runner.active_game.get_node("Enemy2").speed == 140.0, harness.id + " host bridge mutates live game")
            controller._dispatch_host_request({"id": "control", "command": "set_properties", "args": {"targets": [response.nodes[0].handle], "values": {"title": String.chr(1).repeat(1024)}}}, bridge)
            var control = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-control.json")))
            check(control is Dictionary and control.get("ok", false) and control.results[0].values.title == String.chr(1).repeat(1024), harness.id + " bridge preserves escaped control-character mutation outcome")
        controller.queue_free()
    # Controller teardown invalidates its pending tool operations. Finish that
    # teardown before a new reload using the fixture's shared tool instance.
    await process_frame
    for invalid in [{"limit": 101}, {"limit": "many"}, {"depth": -1}, {"depth": 0.5}, {"properties": [1]}, {"group": []}, {"offset": -1}, {"offset": 0.5}, {"offset": "1"}, {"offset": 1001}, {"discover_properties": 1}]:
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
    check("traversal_limit" in result.get("truncated_by", []) and result.get("next_offset") == null, "traversal cutoff requires narrower root")
    var original_script = runner.active_game.get_node("Enemy2").get_script()
    tools.patch_file("enemy.gd", "var speed = 80.0", "var speed = 160.0")
    var future_enemy = original_script.new()
    check(future_enemy.speed == 80.0, "source edits do not hot-reload future instances of loaded scripts")
    future_enemy.free()
    check((await tools.wait_reload(tools.reload_game())).ok and runner.active_game.get_node("Enemy2").speed == 160.0, "reload applies persistent source edits")
    runner.unload_game()
    check(not tools.execute("set_properties", {"targets": [handles[2]], "values": {"speed": 1}}).ok, "unload invalidates handles")
    runner.queue_free()
    await process_frame
    print("Runtime properties: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)
