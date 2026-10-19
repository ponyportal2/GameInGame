extends RefCounted

# Mechanical insertion shared by isolated tests and live application. The caller
# supplies the already-validated parent; no expression evaluation or script swap.
const Properties = preload("res://src/core/runtime_properties.gd")

static func error(reason: String, message: String) -> Dictionary:
    return {"ok": false, "reason": reason, "error": message.left(1500)}

static func script_path(node: Node) -> String:
    var script = node.get_script()
    return ProjectSettings.globalize_path(str(script.resource_path).split("#")[0]) if script != null else ""

static func validate(workspace: String, args: Dictionary) -> Dictionary:
    for key in args:
        if key not in ["parent", "candidate_path", "name", "script_path", "properties"]:
            return error("invalid_arguments", "Unknown argument: " + str(key))
    for key in ["name", "script_path", "candidate_path"]:
        if not args.get(key) is String or args[key].is_empty() or args[key].length() > 1024:
            return error("invalid_arguments", "Expected a nonempty bounded string: " + key)
    var name: String = args.name
    if name.length() > 64 or name.validate_node_name() != name or name in [".", ".."] or name.contains("\n") or name.contains("\r"):
        return error("invalid_name", "Use a valid explicit child name, at most 64 characters.")
    var path = PathUtils.join_workspace(workspace, args.script_path)
    if path == "" or path.get_extension() != "gd" or not FileAccess.file_exists(path):
        return error("invalid_script_path", "script_path must identify an existing workspace .gd file.")
    var props = args.get("properties", {})
    if not props is Dictionary or props.size() > 16:
        return error("invalid_properties", "properties must be an object with at most 16 scalar/value properties.")
    # Bound requests before running game code. Avoid ever truncating an outcome.
    if JSON.stringify(props).to_utf8_buffer().size() > 8192 or JSON.stringify(props).count("\\n") > 100:
        return error("invalid_properties", "Initial properties exceed the 8 KiB / 100 content line budget.")
    for key in props:
        if not key is String or key.length() > 128 or key in ["script", "name", "owner", "unique_name_in_owner"]:
            return error("invalid_properties", "Unsupported initial property name.")
    return {"ok": true, "path": path}

static func insert(runner: Node, workspace: String, parent: Node, args: Dictionary) -> Dictionary:
    if not is_instance_valid(parent) or parent.is_queued_for_deletion() or not parent.is_node_ready():
        return error("parent_not_ready", "Parent must exist and have completed _ready().")
    if parent.get_node_or_null(NodePath(args.name)) != null:
        return error("child_already_present", "Child already present; cold startup is not a late-insertion test.")
    var expected: Dictionary = args.get("expected", {})
    if parent.get_class() != expected.get("class") or script_path(parent) != expected.get("script"):
        return error("parent_mismatch", "Candidate/live parent class or script differs from the inspected live parent.")
    var before = errors(runner)
    # Detach cached workspace resources while compiling the new component. This
    # gives preload dependencies fresh implementations without reloading scripts
    # attached to existing live objects. Restore their original cache afterwards.
    var paths: Array[String] = []
    runner._collect_resources(workspace, paths)
    for path in paths:
        if path.get_extension().to_lower() != "gd": continue
        var violation = preload("res://src/core/script_load_policy.gd").first_violation(FileAccess.get_file_as_string(path))
        if not violation.is_empty():
            return error("script_load_policy", "%s:%d: %s" % [path.get_file(), violation.line, violation.message])
    var previous = runner._detach_cache(paths)
    var script = GDScript.new()
    script.resource_path = workspace.path_join(args.script_path) + "#injection-%d" % Time.get_ticks_usec()
    script.source_code = FileAccess.get_file_as_string(workspace.path_join(args.script_path))
    var compiled = script.reload()
    runner._restore_cache(previous)
    if compiled != OK or errors(runner) > before:
        return error("compile_failed", "Component or a dependency failed to compile. Read returned preflight diagnostics.")
    if not ClassDB.is_parent_class(script.get_instance_base_type(), "Node"):
        return error("not_a_node", "Component script must extend a Node type.")
    var base: Script = script
    while base != null:
        for method in base.get_script_method_list():
            if method.name == "_init" and method.args.size() > method.default_args.size():
                return error("required_constructor_arguments", "Component _init() must be callable without arguments, including inherited constructors.")
        base = base.get_base_script()
    var child = script.new()
    if not is_instance_valid(child):
        return error("constructor_failed", "Component invalidated itself during construction.")
    var result = _initialize(runner, parent, child, args, before)
    if not result.ok and is_instance_valid(child):
        if child.get_parent() != null: child.get_parent().remove_child(child)
        child.queue_free()
    return result

static func _initialize(runner: Node, parent: Node, child: Node, args: Dictionary, before: int) -> Dictionary:
    var helper = Properties.new(runner)
    var props = helper._properties(child)
    if not is_instance_valid(child): return error("initialization_failed", "Property discovery invalidated new child.")
    var decoded := {}
    for key in args.get("properties", {}):
        if not props.has(key) or not helper._supported(props[key]) or int(props[key].usage) & PROPERTY_USAGE_READ_ONLY:
            return error("invalid_properties", "Missing, unsupported or read-only initial property: " + key)
        var type = int(props[key].type)
        if type == TYPE_NIL: type = typeof(child.get(key))
        if not is_instance_valid(child): return error("initialization_failed", "Property getter invalidated new child.")
        var value = helper._decode(args.properties[key], type)
        if not value.ok: return error("invalid_properties", key + ": " + value.error)
        decoded[key] = value.value
    child.name = args.name
    for key in decoded:
        child.set(key, decoded[key])
        if not is_instance_valid(child): return error("initialization_failed", "Property setter invalidated new child.")
    if errors(runner) > before or child.is_queued_for_deletion():
        return error("initialization_failed", "Constructor or initial setters emitted errors or deleted the child.")
    if not is_instance_valid(parent) or parent.is_queued_for_deletion() or not parent.is_inside_tree():
        return error("parent_invalidated", "Parent invalidated during component preparation.")
    if parent.get_node_or_null(NodePath(args.name)) != null:
        return error("child_already_present", "Child name became occupied during component preparation.")
    parent.add_child(child)
    if errors(runner) > before or not helper._within(child, runner.active_game) or child.get_parent() != parent or str(child.name) != args.name:
        return error("live_initialization_failed", "Child initialization failed or changed its identity. Cleanup is not rollback of side effects.")
    runner.runtime_children[child.get_instance_id()] = weakref(child)
    return {"ok": true, "handle": helper._handle(child, runner.active_game)}

static func errors(runner: Node) -> int:
    runner.runtime_log.mutex.lock()
    var count = int(runner.runtime_log.notification_counts.error)
    runner.runtime_log.mutex.unlock()
    return count
