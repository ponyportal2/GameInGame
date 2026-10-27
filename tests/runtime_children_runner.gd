extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
var passed := 0
var failed := 0
var workspace := "user://games/Runtime children"
var runner: Node
var tools: GameTools

func _init() -> void:
    call_deferred("run")

func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if value: passed += 1
    else: failed += 1

func put(source: String, file: String = "main.gd") -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    var out = FileAccess.open(workspace.path_join(file), FileAccess.WRITE)
    out.store_string(source)
    out.close()

func handle(path: String = ".") -> Dictionary:
    return tools.execute("inspect_runtime", {"root": path, "depth": 0}).nodes[0].handle

func request(name: String = "Ability", script: String = "ability.gd") -> Dictionary:
    return {"parent": handle(), "candidate_path": ".", "name": name, "script_path": script, "properties": {"power": 7.0}}

func invoke(args: Dictionary) -> Dictionary:
    return await tools.wait_reload(tools.execute("add_runtime_child", args))

func run() -> void:
    runner = Runner.new()
    root.add_child(runner)
    tools = GameTools.new(workspace, runner)
    put("extends Node\nvar ready_count = 0\nvar cached = []\nfunc _ready():\n\tready_count += 1\n\tcached = get_children()\n")
    check(runner.load_game(workspace).ok, "live fixture loads")
    put("extends Node\nvar power = 1.0\nvar ready_power = 0.0\nvar ready_count = 0\nvar process_count = 0\nvar physics_count = 0\nvar deferred_done = false\nfunc _ready():\n\tready_power = power\n\tready_count += 1\n\tcall_deferred(\"later\")\nfunc later():\n\tdeferred_done = true\nfunc _process(_d):\n\tprocess_count += 1\nfunc _physics_process(_d):\n\tphysics_count += 1\n", "ability.gd")
    var args = request()
    var first = tools.execute("add_runtime_child", args)
    check(first.get("pending", false), "structural tool returns pending instead of blocking host")
    if not first.get("pending", false):
        print(first)
        runner.free()
        quit(1)
        return
    var result: Dictionary = await tools.wait_reload(first)
    if not result.ok:
        print(result)
        runner.free()
        quit(1)
        return
    check(result.ok and result.live_attempted, "passing late preflight applies live")
    check(result.preflight.ok and result.preflight.process_ticks_completed >= 4 and result.preflight.physics_ticks_completed >= 3, "late preflight observes completed execution")
    check(result.preflight.cleanup.stop_method == "graceful", "preflight child exits cleanly")
    var game = runner.active_game
    var child = game.get_node_or_null("Ability")
    check(child != null and child.power == 7 and child.ready_power == 7 and child.ready_count == 1, "initial properties precede child ready")
    check(game.ready_count == 1 and game.cached.is_empty(), "existing parent initialization is unchanged")
    for i in range(8): await process_frame
    check(child.process_count > 0 and child.physics_count > 0 and child.deferred_done, "live late child processes physics and deferred initialization")
    var added_handle = result.handle
    result = await invoke(args)
    check(not result.ok and not result.live_attempted and game.get_child_count() == 1, "duplicate insertion rejected without mutation")
    var remove = await tools.wait_reload(tools.execute("remove_runtime_child", {"target": handle()}))
    check(not remove.ok and not remove.live_attempted, "cannot remove original game nodes")
    remove = await tools.wait_reload(tools.execute("remove_runtime_child", {"target": added_handle}))
    check(remove.ok and not game.has_node("Ability"), "owned child removed without replacing parent")
    remove = await tools.wait_reload(tools.execute("remove_runtime_child", {"target": added_handle}))
    check(not remove.ok, "stale removal rejected")

    args = request()
    args.parent.instance_id = "1"
    result = await invoke(args)
    check(not result.ok and not result.live_attempted, "stale parent rejected")
    args = request()
    args.candidate_path = "Missing"
    result = await invoke(args)
    check(not result.ok and not result.live_attempted, "missing candidate target leaves live untouched")
    for script in ["../outside.gd", "res://src/app.gd"]:
        result = await invoke(request("Ability", script))
        check(not result.ok and not result.live_attempted, "workspace escape rejected")
    put("extends Node\nfunc _init(required):\n\tname = str(required)\n", "required.gd")
    result = await invoke(request("Ability", "required.gd"))
    check(not result.ok and not result.live_attempted, "required constructor rejected")
    put("extends RefCounted\n", "not_node.gd")
    result = await invoke(request("Ability", "not_node.gd"))
    check(not result.ok and not result.live_attempted, "non Node script rejected")
    args = request()
    args.properties = {"missing_property": 4}
    result = await invoke(args)
    check(not result.ok and not result.live_attempted, "invalid properties rejected before live")

    for body in ["func _ready():\n\tget_node(\"Missing\")\n", "func _process(_d):\n\tget_node(\"Missing\")\n", "func _physics_process(_d):\n\tget_node(\"Missing\")\n", "func _ready():\n\tcall_deferred(\"bad\")\nfunc bad():\n\tget_node(\"Missing\")\n"]:
        put("extends Node\nvar power = 1.0\n" + body, "bad.gd")
        result = await invoke(request("Bad", "bad.gd"))
        check(not result.ok and not result.live_attempted and not game.has_node("Bad"), "candidate callback failure prevents live insertion")

    for body in ["func _process(_d):\n\tqueue_free()\n", "func _ready():\n\tcall_deferred(\"later\")\nfunc later():\n\tname = 'Renamed'\n", "func _ready():\n\tcall_deferred(\"later\")\nfunc later():\n\treparent(get_parent().get_parent())\n"]:
        put("extends Node\nvar power = 1.0\n" + body, "vanish.gd")
        result = await invoke(request("Vanish", "vanish.gd"))
        check(not result.ok and not result.live_attempted and not game.has_node("Vanish"), "preflight rejects child deletion or identity change")

    put("extends Node\nvar power = 1.0\nfunc _ready():\n\tif not 'preflights' in OS.get_user_data_dir():\n\t\tget_parent().set_meta(\"side_effect\", true)\n\t\tget_node(\"MissingLiveOnly\")\n", "host_bad.gd")
    result = await invoke(request("Bad", "host_bad.gd"))
    check(not result.ok and result.preflight.ok and result.live_attempted and result.live_game_modified == null, "live-only failure distinguishes preflight from application")
    check(game.has_meta("side_effect") and not game.has_node("Bad"), "failed child cleaned up without claiming rollback")

    # Persistent construction is not a late insertion test.
    put("extends Node\nfunc _ready():\n\tvar n = Node.new()\n\tn.name = 'Ability'\n\tadd_child(n)\n")
    result = await invoke(request())
    check(not result.ok and not result.live_attempted and result.preflight.get("reason") == "child_already_present", "cold-start child collision is not mistaken for late-insertion evidence")
    put("extends Node\nvar ready_count = 0\nvar cached = []\nfunc _ready():\n\tready_count += 1\n\tcached = get_children()\n")
    var pending = tools.execute("add_runtime_child", request())
    while not runner.reload_in_progress: await process_frame
    tools.cancel_reload()
    result = await tools.wait_reload(pending)
    check(not result.ok and not result.live_attempted and result.preflight.cleanup.state == "exited", "cancellation reaps preflight and prevents live application")

    # Code changes after preflight starts must invalidate acceptance.
    pending = tools.execute("add_runtime_child", request())
    while not runner.reload_in_progress: await process_frame
    put("extends Node\nvar changed = true\n", "added_dependency.gd")
    result = await tools.wait_reload(pending)
    if result.get("reason") != "code_changed": print("Source-change rejection: ", result.get("reason"), "; preflight: ", result.get("preflight", {}).get("reason"))
    check(not result.ok and not result.live_attempted and result.reason == "code_changed", "new dependency invalidates tested inputs")

    # Revalidate the name after the test/apply time gap.
    pending = tools.execute("add_runtime_child", request())
    while not runner.reload_in_progress: await process_frame
    var collision = Node.new()
    collision.name = "Ability"
    game.add_child(collision)
    result = await tools.wait_reload(pending)
    check(not result.ok and not result.live_attempted and game.get_node("Ability") == collision, "live name collision after preflight launch is preserved before live attempt")
    game.remove_child(collision)
    collision.free()

    # A component's preload uses new code, without hot-reloading old users.
    put("extends Node\nvar answer = 1\n", "helper.gd")
    var previous_helper = load(workspace.path_join("helper.gd"))
    put("extends Node\nvar answer = 2\n", "helper.gd")
    put("extends Node\nconst Helper = preload('helper.gd')\nvar power = 1.0\nvar answer = 0\nfunc _ready():\n\tvar h = Helper.new()\n\tanswer = h.answer\n\th.free()\n", "fresh.gd")
    result = await invoke(request("Fresh", "fresh.gd"))
    check(result.ok and game.get_node("Fresh").answer == 2, "injected component sees fresh preload dependencies")
    var old_helper = previous_helper.new()
    check(old_helper.answer == 1, "preexisting script implementation is preserved")
    old_helper.free()

    var config_text = '[gd_resource type="Resource" load_steps=2 format=3]\n[sub_resource type="Resource" id="Resource_sub"]\nresource_name = "old"\n[resource]\nresource_name = "old"\nmetadata/child = SubResource("Resource_sub")\n'
    put(config_text, "config.tres")
    var old_config = load(workspace.path_join("config.tres"))
    var old_embedded = old_config.get_meta("child")
    put(config_text.replace('"old"', '"new"'), "config.tres")
    put("extends Node\nconst Config = preload('config.tres')\nvar power = 1.0\nvar answer = Config.resource_name\nvar embedded = Config.get_meta('child').resource_name\n", "serialized.gd")
    result = await invoke(request("Serialized", "serialized.gd"))
    check(result.ok and game.get_node("Serialized").answer == "new", "injection gets fresh serialized preload")
    check(result.ok and game.get_node("Serialized").embedded == "new" and old_embedded.resource_name == "old", "injection refreshes embedded serialized resources without mutating old users")
    check(old_config.resource_name == "old", "existing resource object remains unchanged")
    put("extends Node\nconst Config = preload('config.tres')\nvar answer = Config.resource_name\nvar embedded = Config.get_meta('child').resource_name\n")
    result = await runner.checked_reload(workspace)
    if not result.ok:
        push_error("Serialized-resource reload failed: " + JSON.stringify(result))
    check(result.ok and runner.active_game.answer == "new", "preflighted full reload gets fresh serialized preload")
    check(result.ok and runner.active_game.embedded == "new", "preflighted reload refreshes embedded serialized resources")
    if not result.ok:
        # Later cache rollback checks require this accepted game. Do not turn a
        # useful preflight failure into an invalid-property exception and hang.
        runner.free()
        quit(1)
        return
    check(old_config.resource_name == "old", "full reload preserves previous resource object")
    var accepted_config = ResourceLoader.get_cached_ref(workspace.path_join("config.tres"))
    var accepted_embedded = accepted_config.get_meta("child")
    put(config_text.replace('"old"', '"rejected"'), "config.tres")
    put("extends Node\nconst Config = preload('config.tres')\nfunc _ready():\n\tget_node('Missing')\n")
    result = runner.load_game(workspace)
    check(not result.ok and runner.active_game.answer == "new" and ResourceLoader.get_cached_ref(workspace.path_join("config.tres")) == accepted_config, "rejected candidate restores serialized resource cache and previous game")
    check(ResourceLoader.get_cached_ref(accepted_embedded.resource_path) == accepted_embedded and accepted_embedded.resource_name == "new", "rejection restores embedded resource cache identity")
    # Restore the original live parent for the remaining identity/bridge checks.
    put("extends Node\nvar ready_count = 0\nvar cached = []\nfunc _ready():\n\tready_count += 1\n\tcached = get_children()\n")
    check(runner.load_game(workspace).ok, "restore live parent after serialized reload")
    game = runner.active_game

    put("extends Node\nvar power = 1.0\nfunc _process(_d):\n\twhile true: pass\n", "hang.gd")
    runner.preflight_timeout_ms = 1800
    result = await invoke(request("Hung", "hang.gd"))
    check(not result.ok and not result.live_attempted and result.preflight.reason == "timeout" and result.preflight.cleanup.state == "exited", "hung injected component times out and is reaped")
    runner.preflight_timeout_ms = 15000

    # The actual inherited bridge waits for completion, not a pending placeholder.
    var agent = preload("res://src/agent/opencode_agent_controller.gd").new()
    root.add_child(agent)
    agent.set_process(false)
    agent.tools = tools
    agent.bridge_dir = ProjectSettings.globalize_path("user://runtime-child-bridge")
    DirAccess.make_dir_recursive_absolute(agent.bridge_dir)
    agent._dispatch_host_request({"id": "add", "command": "add_runtime_child", "args": request("ViaBridge")}, agent.bridge_dir)
    check(not agent.pending_reload.is_empty() and not game.has_node("ViaBridge"), "child addition waits for player approval by default")
    agent.approve_reload()
    var response_path = agent.bridge_dir.path_join("response-add.json")
    var deadline = Time.get_ticks_msec() + 25000
    while not FileAccess.file_exists(response_path) and Time.get_ticks_msec() < deadline: await process_frame
    var response = JsonStore.read_dict(response_path, {})
    check(response.get("ok", false) and not response.get("pending", true) and game.has_node("ViaBridge"), "OpenCode inherited bridge delivers final insertion outcome")
    agent._dispatch_host_request({"id": "remove", "command": "remove_runtime_child", "args": {"target": response.get("handle", {})}}, agent.bridge_dir)
    response_path = agent.bridge_dir.path_join("response-remove.json")
    while not FileAccess.file_exists(response_path) and Time.get_ticks_msec() < deadline: await process_frame
    check(JsonStore.read_dict(response_path, {}).get("ok", false) and not game.has_node("ViaBridge"), "bridge delivers final removal outcome")
    agent.free()
    await process_frame
    var settings_store = preload("res://src/core/metadata_store.gd").new()
    var saved_settings = settings_store.global_settings()
    for harness in preload("res://src/agent/harness_inventory.gd").all():
        var controller = load("res://" + harness.controller).new()
        root.add_child(controller)
        controller.set_process(false)
        controller.tools = tools
        controller.bridge_dir = ProjectSettings.globalize_path("user://approval-" + harness.id)
        DirAccess.make_dir_recursive_absolute(controller.bridge_dir)
        var settings = saved_settings.duplicate(true)
        settings.auto_approve_reloads = true
        settings.auto_approve_runtime_children = false
        settings_store.save_global_settings(settings)
        controller._dispatch_host_request({"id": "manual", "command": "add_runtime_child", "args": {}}, controller.bridge_dir)
        check(not controller.pending_reload.is_empty(), harness.id + " reload auto-approval does not authorize child code")
        controller.operation_id += 1
        controller.approve_reload()
        check(controller.pending_reload.is_empty() and not FileAccess.file_exists(controller.bridge_dir.path_join("response-manual.json")), harness.id + " stale approval cannot execute child code")
        controller._dispatch_host_request({"id": "cancelled", "command": "add_runtime_child", "args": {}}, controller.bridge_dir)
        controller.restart_runtime()
        check(controller.pending_reload.is_empty(), harness.id + " cancellation/restart discards pending child approval")
        controller.bridge_dir = ProjectSettings.globalize_path("user://approval-" + harness.id)
        settings.auto_approve_reloads = false
        settings.auto_approve_runtime_children = true
        settings_store.save_global_settings(settings)
        controller._dispatch_host_request({"id": "automatic", "command": "add_runtime_child", "args": {}}, controller.bridge_dir)
        var automatic_path = controller.bridge_dir.path_join("response-automatic.json")
        for i in range(10):
            if FileAccess.file_exists(automatic_path): break
            await process_frame
        check(controller.pending_reload.is_empty() and FileAccess.file_exists(automatic_path), harness.id + " independent child auto-approval dispatches to validation")
        controller.free()
    settings_store.save_global_settings(saved_settings)
    check(runner.active_game == game, "all operations preserve live root identity")
    runner.free()
    print("Runtime children: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)
