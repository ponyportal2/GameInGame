extends RefCounted

# These operations run on the host main thread. Setters/getters are game code:
# effects cannot be rolled back and readback describes only this instant.
const MAX_NODES = 100
const MAX_VISITED = 1000
const MAX_PROPERTIES = 16
const MAX_STRING = 1024
const SUPPORTED = [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]

var runner: Node

func _init(game_runner: Node) -> void:
    runner = game_runner

func _error(message: String) -> Dictionary:
    return {"ok": false, "error": message}

func _game() -> Node:
    if not is_instance_valid(runner) or not _alive(runner.active_game):
        return null
    return runner.active_game

func _alive(node: Variant) -> bool:
    return is_instance_valid(node) and not node.is_queued_for_deletion()

func _within(node: Variant, game: Variant) -> bool:
    if not _alive(node) or not _alive(game) or _game() != game: return false
    var ancestor = node
    while ancestor != null:
        if not _alive(ancestor): return false
        if ancestor == game: return true
        ancestor = ancestor.get_parent()
    return false

func _path(game: Node, path: Variant) -> Node:
    if not path is String or path.length() > MAX_STRING or path == "" or path.begins_with("/") or ":" in path or ".." in path.split("/"):
        return null
    var node = game.get_node_or_null(NodePath(path))
    return node if _within(node, game) else null

func _handle(node: Node, game: Node) -> Dictionary:
    # IDs are strings because native JSON consumers cannot represent all int64s.
    return {"path": str(game.get_path_to(node)), "instance_id": str(node.get_instance_id()), "game_generation": str(game.get_instance_id())}

func _resolve(handle: Dictionary, game: Node) -> Node:
    if handle.get("game_generation") != str(game.get_instance_id()):
        return null
    var node = _path(game, handle.get("path"))
    if node == null or handle.get("instance_id") != str(node.get_instance_id()):
        return null
    return node

func _properties(node: Node) -> Dictionary:
    var result = {}
    for info in node.get_property_list():
        if int(info.get("usage", 0)) & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
            continue
        result[str(info.name)] = info
    return result

func _supported(info: Dictionary) -> bool:
    # Untyped script fields are common in generated games. Inspect only requested
    # values; mutation infers their current scalar/value type, never object types.
    return info.get("type", TYPE_NIL) in SUPPORTED or info.get("type") == TYPE_NIL

func _encode(value: Variant) -> Dictionary:
    match typeof(value):
        TYPE_BOOL, TYPE_INT:
            if typeof(value) == TYPE_INT and (value < -9007199254740991 or value > 9007199254740991):
                return _error("Integer exceeds exact JSON range.")
            return {"ok": true, "value": value}
        TYPE_FLOAT:
            if is_finite(value): return {"ok": true, "value": value}
        TYPE_STRING, TYPE_STRING_NAME:
            if str(value).length() <= MAX_STRING: return {"ok": true, "value": str(value)}
        TYPE_VECTOR2:
            if value.is_finite(): return {"ok": true, "value": {"type": "Vector2", "x": value.x, "y": value.y}}
        TYPE_VECTOR3:
            if value.is_finite(): return {"ok": true, "value": {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}}
        TYPE_COLOR:
            if is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a):
                return {"ok": true, "value": {"type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}}
    return _error("Unsupported, oversized, or non-finite value.")

func _decode(value: Variant, type: int) -> Dictionary:
    if type in [TYPE_FLOAT, TYPE_INT] and typeof(value) in [TYPE_FLOAT, TYPE_INT]:
        if not is_finite(float(value)) or abs(float(value)) > 9007199254740991 or (type == TYPE_INT and float(value) != floor(float(value))):
            return _error("Expected a finite number; integers must be exact JSON integers.")
        return {"ok": true, "value": int(value) if type == TYPE_INT else float(value)}
    if type in [TYPE_STRING, TYPE_STRING_NAME] and value is String and value.length() <= MAX_STRING:
        return {"ok": true, "value": StringName(value) if type == TYPE_STRING_NAME else value}
    if type == TYPE_BOOL and value is bool:
        return {"ok": true, "value": value}
    var components: Array = []
    var tag = ""
    match type:
        TYPE_VECTOR2: components = ["x", "y"]; tag = "Vector2"
        TYPE_VECTOR3: components = ["x", "y", "z"]; tag = "Vector3"
        TYPE_COLOR: components = ["r", "g", "b", "a"]; tag = "Color"
    if components.is_empty() or not value is Dictionary or value.get("type") != tag or value.size() != components.size() + 1:
        return _error("Value does not match property type " + type_string(type) + ".")
    for key in components:
        if typeof(value.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value[key])):
            return _error("Expected finite numeric components.")
    var decoded: Variant
    match type:
        TYPE_VECTOR2: decoded = Vector2(value.x, value.y)
        TYPE_VECTOR3: decoded = Vector3(value.x, value.y, value.z)
        TYPE_COLOR: decoded = Color(value.r, value.g, value.b, value.a)
    var encoded = _encode(decoded)
    return {"ok": true, "value": decoded} if encoded.ok else encoded

func inspect(args: Dictionary) -> Dictionary:
    for key in args:
        if key not in ["root", "depth", "limit", "offset", "discover_properties", "class", "script", "group", "properties"]:
            return _error("Unknown argument '%s'. Use 'root' to select the inspection root; 'path' is not an inspection argument." % str(key).left(64))
    var game = _game()
    if game == null: return _error("No active game.")
    var generation = str(game.get_instance_id())
    var origin = _path(game, args.get("root", "."))
    if origin == null: return _error("Root must be a node path beneath active_game, without parent traversal or subnames.")
    var discover = args.get("discover_properties", false)
    if not discover is bool: return _error("Expected discover_properties boolean.")
    var depth = args.get("depth", 0 if discover else 3)
    var offset = args.get("offset", 0)
    if typeof(offset) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(offset)) or offset < 0 or offset > MAX_VISITED or offset != int(offset):
        return _error("Expected offset 0..1000.")
    var limit = args.get("limit", 1 if discover else MAX_NODES)
    var requested = args.get("properties", [])
    if typeof(depth) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(depth)) or depth < 0 or depth > 8 or depth != int(depth) or typeof(limit) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(limit)) or limit < 1 or limit > MAX_NODES or limit != int(limit):
        return _error("Expected depth 0..8 and limit 1..100.")
    if discover and limit > 3: return _error("Property discovery accepts at most 3 nodes; inspect one representative node or page with offset.")
    if not requested is Array or requested.size() > MAX_PROPERTIES:
        return _error("Request at most 16 properties.")
    for name in requested:
        if not name is String or name.length() > MAX_STRING: return _error("Expected property names.")
    for key in ["class", "script", "group"]:
        if not args.get(key, "") is String or args.get(key, "").length() > MAX_STRING: return _error("Expected bounded string filters.")
    var pending = [{"id": origin.get_instance_id(), "depth": 0}]
    var nodes: Array = []
    var visited = 0
    var reasons: Array = []
    var matched = 0
    var has_more = false
    while not pending.is_empty() and visited < MAX_VISITED:
        var item: Dictionary = pending.pop_back()
        var node = instance_from_id(item.id)
        if not node is Node or not _within(node, game): continue
        visited += 1
        var script: Script = node.get_script()
        var script_path = script.resource_path if script != null else ""
        if (args.get("class", "") == "" or node.is_class(args["class"])) and (args.get("script", "") == "" or args.script == script_path) and (args.get("group", "") == "" or node.is_in_group(args.group)):
            matched += 1
            if matched > offset and nodes.size() >= limit:
                has_more = true
                if "result_limit" not in reasons: reasons.append("result_limit")
                break
            # Skip matching nodes, not visited nodes; do not invoke skipped getters.
            if matched > offset:
                var entry = {"handle": _handle(node, game), "class": node.get_class(), "values": {}}
                var props = _properties(node)
                if not _within(node, game): return _error("Game or node invalidated during property discovery.")
                if discover:
                    entry.script = script_path
                    entry.scene_file_path = node.scene_file_path
                    entry.groups = []
                    for group in node.get_groups().slice(0, 32): entry.groups.append(str(group).left(MAX_STRING))
                    entry.available_properties = []
                    entry.properties_truncated = false
                    for name in props:
                        if _supported(props[name]):
                            if entry.available_properties.size() < 64:
                                entry.available_properties.append({"name": name.left(MAX_STRING), "type": "Variant" if props[name].type == TYPE_NIL else type_string(props[name].type)})
                            else: entry.properties_truncated = true
                entry.property_errors = {}
                for name in requested:
                    if not _within(node, game):
                        entry.property_errors[name] = "Node invalidated during inspection."
                        continue
                    if not props.has(name) or not _supported(props[name]):
                        entry.property_errors[name] = "Missing or unsupported property."
                        continue
                    var encoded = _encode(node.get(name))
                    if not _within(node, game): return _error("Game or node invalidated by a property getter.")
                    if encoded.ok: entry.values[name] = encoded.value
                    else: entry.property_errors[name] = encoded.error
                if entry.property_errors.is_empty(): entry.erase("property_errors")
                nodes.append(entry)
        if not _within(node, game): continue
        if item.depth >= depth:
            if node.get_child_count() > 0 and "depth_limit" not in reasons: reasons.append("depth_limit")
            continue
        # Bound traversal storage even for extremely wide trees.
        var count = mini(node.get_child_count(), MAX_VISITED - visited - pending.size())
        if count < node.get_child_count() and "traversal_limit" not in reasons: reasons.append("traversal_limit")
        for index in range(count - 1, -1, -1):
            pending.append({"id": node.get_child(index).get_instance_id(), "depth": item.depth + 1})
    if not pending.is_empty() and visited >= MAX_VISITED and "traversal_limit" not in reasons:
        reasons.append("traversal_limit")
    var result = {"ok": true, "nodes": nodes, "visited": visited, "truncated": not reasons.is_empty(), "truncated_by": reasons, "has_more": has_more, "next_offset": int(offset) + nodes.size() if has_more else null, "game_generation": generation}
    if nodes.is_empty() and not reasons.is_empty():
        var hints: Array[String] = ["Search incomplete; zero returned nodes does not prove there are no matches."]
        if "depth_limit" in reasons:
            hints.append("Depth limit reached: increase depth or choose a narrower root. Property discovery defaults to depth 0 at root, even with a class filter.")
        if "traversal_limit" in reasons:
            hints.append("Traversal limit reached: choose a narrower root.")
        result.recovery = " ".join(hints)
    return result

func set_properties(args: Dictionary) -> Dictionary:
    var game = _game()
    if game == null: return _error("No active game.")
    var targets = args.get("targets")
    var values = args.get("values")
    if not targets is Array or targets.is_empty() or targets.size() > MAX_NODES or not values is Dictionary or values.is_empty() or values.size() > MAX_PROPERTIES:
        return _error("Expected 1..100 explicit target handles and 1..16 property values.")
    var seen = {}
    for handle in targets:
        if not handle is Dictionary or not handle.get("instance_id") is String or not handle.get("game_generation") is String or not handle.get("path") is String or seen.has(handle.instance_id):
            return _error("Expected unique inspection handles with string path, instance_id and game_generation.")
        seen[handle.instance_id] = true
    for name in values:
        if not name is String or name.length() > MAX_STRING: return _error("Expected bounded property names.")
    var results: Array = []
    var changed = 0
    var failures = 0
    for handle in targets:
        var result = _set_target(handle, values, game)
        results.append(result)
        if result.ok: changed += 1
        else: failures += 1
    return {"ok": failures == 0, "matched": targets.size(), "changed": changed, "failed": failures, "results": results, "temporary": true}

func _set_target(handle: Dictionary, values: Dictionary, game: Variant) -> Dictionary:
    var result = {"ok": false, "handle": handle, "values": {}, "applied": [], "error": ""}
    if not _alive(game):
        result.error = "Game invalidated."
        return result
    var node = _resolve(handle, game)
    if node == null:
        result.error = "Stale handle or target outside active_game. Inspect again."
        return result
    var props = _properties(node)
    if not _within(node, game):
        result.error = "Target invalidated during property discovery."
        return result
    var decoded = {}
    for name in values:
        if not props.has(name) or not _supported(props[name]) or (int(props[name].usage) & PROPERTY_USAGE_READ_ONLY) != 0:
            result.error = "Missing, unsupported, or read-only property: " + name
            return result
        var type = int(props[name].type)
        if type == TYPE_NIL:
            type = typeof(node.get(name))
            if not _within(node, game):
                result.error = "Target invalidated while inspecting current property type."
                return result
        var value = _decode(values[name], type)
        if not value.ok:
            result.error = name + ": " + value.error
            return result
        decoded[name] = value.value
    for name in decoded:
        if not _within(node, game):
            result.error = "Target invalidated during mutation; earlier writes may have applied."
            return result
        node.set(name, decoded[name])
        result.applied.append(name)
        if not _within(node, game):
            result.error = "Setter invalidated target; earlier writes may have applied."
            return result
    # Read after all writes: a later setter may change an earlier property.
    for name in decoded:
        if not _within(node, game):
            result.error = "Target invalidated during readback; writes already applied."
            return result
        var encoded = _encode(node.get(name))
        if not _within(node, game):
            result.error = "Getter invalidated target during readback; writes already applied."
            return result
        if not encoded.ok:
            result.error = name + ": " + encoded.error + " Writes already applied."
            return result
        result.values[name] = encoded.value
    result.ok = true
    result.handle = _handle(node, game)
    return result
