extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")
var passed := 0
var failed := 0
var agent: Node
var serial := 0
var poll_calls := 0
var workspace := "user://games/Workflow"

func _init():
    call_deferred("run")

func check(value: bool, label: String):
    print(("PASS: " if value else "FAIL: ") + label)
    if value: passed += 1
    else: failed += 1

func put(file: String, source: String):
    var f = FileAccess.open(workspace.path_join(file), FileAccess.WRITE)
    f.store_string(source)
    f.close()

func command(name: String, args: Dictionary) -> Dictionary:
    serial += 1
    var id = str(serial)
    agent._dispatch_host_request({"id": id, "command": name, "args": args}, agent.bridge_dir)
    var path = agent.bridge_dir.path_join("response-" + id + ".json")
    var deadline = Time.get_ticks_msec() + 15000
    while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
        agent._service_pending_test_commands()
        await process_frame
    return JsonStore.read_dict(path, {"ok": false, "error": "Bridge deadline"})

func action(id: String, args: Dictionary) -> Dictionary:
    args = args.duplicate(true)
    args.run_id = id
    return await command("test_game_action", args)

# The public bridge may legitimately return pending under load. Never submit a
# second action until that exact ID finishes; keep the fast-path checks separate.
func settled_action(id: String, args: Dictionary) -> Dictionary:
    var result = await action(id, args)
    var deadline = Time.get_ticks_msec() + 10000
    while result.get("pending", false) and Time.get_ticks_msec() < deadline:
        await create_timer(0.1).timeout
        poll_calls += 1
        result = await action(id, {"action": "poll", "action_id": result.action_id})
    return result

func inspect_run(id: String, args: Dictionary) -> Dictionary:
    args = args.duplicate(true)
    args.run_id = id
    var result = await command("inspect_runtime", args)
    var deadline = Time.get_ticks_msec() + 10000
    while result.get("pending", false) and Time.get_ticks_msec() < deadline:
        await create_timer(0.05).timeout
        result = await action(id, {"action": "poll", "action_id": result.action_id})
    return result

func inspect_checks(id: String, runner: Node) -> void:
    var spawned = await settled_action(id, {"action": "call", "method": "spawn_inspection_fixture"})
    check(spawned.get("ok", false), "detached inspection fixture creates 215 siblings")
    var handles: Array = []
    for offset in [0, 100, 200]:
        var page = await inspect_run(id, {"class": "Node2D", "group": "inspection", "properties": ["position"], "offset": offset, "limit": 100})
        check(page.get("ok", false) and page.get("scope") == "detached" and page.get("run_id") == id, "detached inspection returns explicit scope through public bridge")
        check(page.get("nodes", []).size() == (15 if offset == 200 else 100) and page.get("next_offset") == (null if offset == 200 else offset + 100), "detached matching-node pagination retains all siblings")
        for item in page.get("nodes", []):
            var index = handles.size()
            var position = item.values.get("position", {})
            check(item.handle.path == "Enemy%d" % index and position.get("type") == "Vector2" and position.get("x") == index and position.get("y") == index * 2, "detached requested properties belong to each actual matching node")
            check(item.handle.get("scope") == "detached" and item.handle.get("run_id") == id and str(item.handle.game_generation).begins_with("detached:" + id + ":"), "detached identity is namespaced per run")
            handles.append(item.handle)
    check(handles.size() == 215 and not runner.active_game.has_node("Enemy0"), "inspection stays in detached tree")
    var actual_id = await settled_action(id, {"action": "call", "method": "inspection_instance_id"})
    check(not handles.is_empty() and handles[0].instance_id == actual_id.get("value"), "inspection instance identity matches actual detached node")
    var discovered = await inspect_run(id, {"discover_properties": true, "root": "."})
    var filtered = await inspect_run(id, {"script": discovered.get("nodes", [{}])[0].get("script", ""), "depth": 0})
    check(filtered.get("nodes", []).size() == 1, "detached inspector supports actual script filters and discovery")
    for args in [{"root": "../Enemy0"}, {"root": "Missing"}]:
        var result = await inspect_run(id, args)
        check(not result.ok and result.get("reason") == ("invalid_root" if args.root.begins_with("..") else "root_not_found") and result.get("scope") == "detached" and result.get("run_id") == id, "detached root errors distinguish syntax and absence with scope")
    var legacy = await settled_action(id, {"action": "inspect", "depth": 1, "properties": ["ready_count"]})
    check(legacy.has("children") and legacy.get("properties", {}).get("ready_count") == "1" and not legacy.has("nodes"), "legacy nested inspect response remains compatible")
    var invalid_legacy = await settled_action(id, {"action": "inspect", "path": "../escape"})
    check(invalid_legacy.get("reason") == "invalid_root" and invalid_legacy.get("scope") == "detached", "legacy inspect path errors also distinguish malformed roots")
    var unknown = await inspect_run("unknown-run", {})
    check(not unknown.ok and unknown.get("scope") == "detached" and unknown.get("run_id") == "unknown-run", "unknown detached runs use supervisor rejection without falling back live")
    for invalid_id in ["", 42]:
        var invalid = await command("inspect_runtime", {"run_id": invalid_id})
        check(not invalid.ok and invalid.get("reason") == "invalid_run_id" and invalid.get("scope") == "detached", "invalid run selection never falls back live")
    JsonStore.write_dict(agent.tools.tests()._test_root().path_join("retention.json"), {"expired": [{"run_id": "expired-run"}]})
    var expired = await inspect_run("expired-run", {})
    check(not expired.ok and expired.get("error") == "retention_expired" and expired.get("run_id") == "expired-run" and expired.get("scope") == "detached", "expired runs use existing retention rejection")
    var pending = await command("inspect_runtime", {"run_id": id, "root": ".", "depth": 0, "properties": ["slow_read"]})
    check(pending.get("pending", false) and pending.get("scope") == "detached" and pending.get("run_id") == id, "slow inspection preserves detached provenance when bounded wait expires")
    var deadline = Time.get_ticks_msec() + 5000
    while pending.get("pending", false) and Time.get_ticks_msec() < deadline:
        await create_timer(0.1).timeout
        pending = await action(id, {"action": "poll", "action_id": pending.action_id})
    check(pending.get("ok", false) and pending.get("nodes", [{}])[0].get("values", {}).get("slow_read") == 42 and pending.get("scope") == "detached", "existing poll completes the exact detached inspection")
    var reads = await inspect_run(id, {"depth": 0, "properties": ["slow_reads"]})
    check(reads.get("nodes", [{}])[0].get("values", {}).get("slow_reads") == 1, "polling never repeats a property getter")

func run():
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    put("main.gd", "extends Node3D\nvar mode = 'menu'\nvar ready_count = 0\nvar cam = null\nvar pos = Vector3.ZERO\nvar fx = null\nvar enemies = []\nvar explosions = 0\nvar damage = 0.0\nfunc _ready():\n\tready_count += 1\nfunc start_play():\n\tmode = 'playing'\nfunc _explode_at(_at, _radius, amount, _owner):\n\texplosions += 1\n\tdamage += amount\nfunc slow():\n\tOS.delay_msec(900)\n\treturn 7\nfunc announce():\n\tprint('AFTER_CURSOR')\n")
    put("grenade.gd", FileAccess.get_file_as_string("res://tests/fixtures/warframe-grenade.gd"))
    put("main.gd", FileAccess.get_file_as_string(workspace.path_join("main.gd")) + "\nvar slow_reads := 0\nvar slow_read: int:\n\tget:\n\t\tslow_reads += 1\n\t\tOS.delay_msec(650)\n\t\treturn 42\n")
    put("main.gd", FileAccess.get_file_as_string(workspace.path_join("main.gd")) + "\nfunc spawn_inspection_fixture():\n\tfor i in range(215):\n\t\tvar child = Node2D.new()\n\t\tchild.name = 'Enemy%d' % i\n\t\tchild.position = Vector2(i, i * 2)\n\t\tadd_child(child)\n\t\tchild.add_to_group('inspection')\nfunc inspection_instance_id():\n\treturn str(get_node('Enemy0').get_instance_id())\n")
    var earlier_log = preload("res://src/core/runtime_log.gd").new()
    earlier_log.start(workspace.get_file(), workspace)
    earlier_log.add("print", "EARLIER_SESSION_ONLY")
    var earlier_session = earlier_log.session_id
    earlier_log.close()
    var runner = Runner.new()
    root.add_child(runner)
    check(runner.load_game(workspace).ok, "host fixture loads")
    agent = preload("res://src/agent/opencode_agent_controller.gd").new()
    root.add_child(agent)
    agent.set_process(false)
    agent.tools = GameTools.new(workspace, runner)
    agent.bridge_dir = ProjectSettings.globalize_path("user://workflow-bridge")
    DirAccess.make_dir_recursive_absolute(agent.bridge_dir)
    var logs = await command("read_runtime_log", {"raw": true})
    var cursor = logs.get("next_cursor", 0)
    runner.runtime_log.add("print", "AFTER_LIVE_CURSOR")
    logs = await command("read_runtime_log", {"cursor": cursor})
    check(not logs.get("records", []).is_empty(), "public runtime cursor returns new records")
    for record in logs.get("records", []): check(record.seq > cursor, "runtime cursor is exclusive")
    logs = await command("read_runtime_log", {"session_id": earlier_session, "raw": true})
    check(logs.get("ok", false) and logs.get("session_id") == earlier_session and earlier_session != runner.runtime_log.session_id, "public runtime log selects a non-current session")
    check(logs.get("records", []).any(func(record): return record.message == "EARLIER_SESSION_ONLY") and not logs.get("records", []).any(func(record): return record.message == "AFTER_LIVE_CURSOR"), "selected session contains historical evidence without current-session records")
    var started = await command("start_test_game", {"mode": "headless"})
    var id = str(started.get("run_id", ""))
    var deadline = Time.get_ticks_msec() + 15000
    while agent.tools.tests().status(id).get("state") == "starting" and Time.get_ticks_msec() < deadline:
        await process_frame
    check(agent.tools.tests().status(id).get("state") == "running", "one detached process reaches smoke-tested running")
    await inspect_checks(id, runner)
    var result = await action(id, {"action": "inspect", "properties": ["ready_count"]})
    check(result.get("ok", false) and not result.get("pending", true), "fast action returns actual result without a poll")
    result = await action(id, {"action": "call", "method": "start_play"})
    check(result.get("ok", false) and not result.get("pending", true), "gameplay setup completes in same call")
    var injection = {"action": "inject_child", "candidate_path": ".", "name": "Grenade", "script_path": "grenade.gd"}
    result = await settled_action(id, injection)
    check(result.get("ok", false) and not result.get("pending", true) and result.get("process_ticks_completed", 0) >= 4 and result.get("physics_ticks_completed", 0) >= 3, "detached late injection returns completed survival smoke")
    check(not runner.active_game.has_node("Grenade") and agent.pending_reload.is_empty(), "detached injection neither touches live game nor requests live approval")
    result = await action(id, {"action": "mouse_button", "button_index": 3, "pressed": true, "position": {"x": 20, "y": 30}})
    check(result.get("ok", false) and not result.get("pending", true), "actual middle mouse press accepted")
    result = await action(id, {"action": "mouse_button", "button_index": 3, "pressed": false})
    check(result.get("ok", false), "actual middle mouse release accepted")
    await create_timer(2.0).timeout
    result = await action(id, {"action": "inspect", "properties": ["explosions", "damage", "ready_count"]})
    check(result.get("properties", {}).get("explosions") == "1" and float(result.get("properties", {}).get("damage", "0")) == 650.0, "original grenade fuse/gravity/damage produces one durable explosion")
    check(result.get("properties", {}).get("ready_count") == "1", "late injection does not repeat parent ready")
    result = await settled_action(id, injection)
    check(not result.get("ok", true) and result.get("reason") == "child_already_present", "duplicate detached injection is rejected")
    injection.name = "Mismatch"
    injection.expected = {"class": "Timer", "script": "main.gd"}
    result = await settled_action(id, injection)
    check(not result.get("ok", true) and result.get("reason") == "parent_mismatch", "explicit detached parent expectations are checked")
    injection.erase("expected")
    injection.path = "."
    result = await settled_action(id, injection)
    check(not result.get("ok", true) and result.get("reason") == "invalid_arguments", "injection rejects ignored path argument")
    injection.erase("path")
    put("vanish.gd", "extends Node\nfunc _process(_d):\n\tqueue_free()\n")
    result = await settled_action(id, {"action": "inject_child", "candidate_path": ".", "name": "Vanish", "script_path": "vanish.gd"})
    check(not result.get("ok", true) and result.get("reason") == "injected_child_changed", "public detached injection rejects clean disappearance during smoke")
    injection.name = "Escape"
    injection.candidate_path = "../.."
    result = await settled_action(id, injection)
    check(not result.get("ok", true), "detached injection cannot escape game root")
    result = await settled_action(id, {"action": "mouse_button", "button_index": 99})
    check(not result.get("ok", true), "unsupported mouse button rejected")
    result = await settled_action(id, {"action": "mouse_button", "button_index": 3, "position": {"x": "bad", "y": 0}})
    check(not result.get("ok", true), "invalid mouse position rejected")
    logs = await command("read_test_log", {"run_id": id, "raw": true})
    cursor = logs.get("next_cursor", 0)
    await settled_action(id, {"action": "call", "method": "announce"})
    await create_timer(0.3).timeout # diagnostic writer flushes asynchronously
    logs = await command("read_test_log", {"run_id": id, "cursor": cursor})
    check(not logs.get("records", []).is_empty(), "public test cursor returns new records")
    for record in logs.get("records", []): check(record.seq > cursor, "test cursor is exclusive")
    var before = Time.get_ticks_msec()
    result = await action(id, {"action": "call", "method": "slow"})
    check(result.get("pending", false) and Time.get_ticks_msec() - before < 800, "slow action returns pending within bounded wait")
    var pending_id = result.get("action_id", "")
    logs = await command("read_test_log", {"run_id": id})
    check(logs.get("ok", false), "logs remain available while child action is pending")
    await create_timer(1.0).timeout
    result = await action(id, {"action": "poll", "action_id": pending_id})
    check(result.get("ok", false) and not result.get("pending", true) and result.get("value") == "7", "same action ID completes without resubmission")
    result = await command("stop_test_game", {"run_id": id})
    check(result.get("state") == "exited" and result.get("stop_method") == "graceful", "single detached process stops cleanly")
    var ended = await inspect_run(id, {})
    check(not ended.ok and ended.get("scope") == "detached" and ended.get("run_id") == id, "exited detached run cannot inspect or fall back live")
    agent.free()
    runner.free()
    print("WORKFLOW TESTS: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
