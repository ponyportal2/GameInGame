extends "res://tests/test_workflow_runner.gd"

# Optional local acceptance: pass a disposable COPY, never the player's workspace.
# GAMESMITH_GRENADE_REPLAY_COPY must contain the original main.gd and grenade.gd.
func run():
    var began = Time.get_ticks_msec()
    workspace = OS.get_environment("GAMESMITH_GRENADE_REPLAY_COPY")
    if workspace.is_empty() or not FileAccess.file_exists(workspace.path_join("grenade.gd")):
        push_error("Provide GAMESMITH_GRENADE_REPLAY_COPY pointing at a disposable game copy.")
        quit(1)
        return
    var source_hash = FileAccess.get_sha256(workspace.path_join("grenade.gd"))
    var main_hash = FileAccess.get_sha256(workspace.path_join("main.gd"))
    # Observer records durable evidence, without changing grenade code/constants.
    put("replay_observer.gd", "extends Node\nvar seen_projectile = false\nvar damage = 0.0\nvar tracked = {}\nvar before_hp = 0.0\nfunc _ready():\n\tvar game = get_parent()\n\tgame._spawn_enemy('boss', false)\n\ttracked = game.enemies[-1]\n\ttracked.pos = game.cam.global_position - game.cam.global_transform.basis.z * 4.0\n\ttracked.pos.y = 0.0\n\ttracked.rig.root.position = tracked.pos\n\tbefore_hp = tracked.hp\nfunc _process(_dt):\n\tvar grenade = get_parent().get_node_or_null('GrenadeReplay')\n\tif grenade != null and not grenade._grenades.is_empty(): seen_projectile = true\n\tif not tracked.is_empty(): damage = maxf(damage, before_hp - float(tracked.hp))\n")
    var runner = Runner.new()
    root.add_child(runner)
    agent = preload("res://src/agent/opencode_agent_controller.gd").new()
    root.add_child(agent)
    agent.set_process(false)
    agent.tools = GameTools.new(workspace, runner)
    agent.bridge_dir = ProjectSettings.globalize_path("user://replay-bridge")
    DirAccess.make_dir_recursive_absolute(agent.bridge_dir)
    var started = await command("start_test_game", {"mode": "headless"})
    var id = str(started.get("run_id", ""))
    var deadline = Time.get_ticks_msec() + 20000
    while agent.tools.tests().status(id).get("state") == "starting" and Time.get_ticks_msec() < deadline: await process_frame
    check(agent.tools.tests().status(id).get("state") == "running", "actual game copy passes startup smoke")
    var result = await settled_action(id, {"action": "call", "method": "start"})
    check(result.get("ok", false) and not result.get("pending", true), "actual game enters gameplay before injection")
    result = await settled_action(id, {"action": "inject_child", "candidate_path": ".", "name": "ReplayObserver", "script_path": "replay_observer.gd"})
    check(result.get("ok", false) and not result.get("pending", true), "observer late-injected in same process")
    result = await settled_action(id, {"action": "inject_child", "candidate_path": ".", "name": "GrenadeReplay", "script_path": "grenade.gd"})
    check(result.get("ok", false) and not result.get("pending", true), "original grenade late-injected with survival smoke")
    result = await settled_action(id, {"action": "mouse_button", "button_index": 3, "pressed": true})
    check(result.get("ok", false), "middle mouse press delivered")
    result = await settled_action(id, {"action": "mouse_button", "button_index": 3, "pressed": false})
    check(result.get("ok", false), "middle mouse release delivered")
    await create_timer(2.0).timeout
    result = await settled_action(id, {"action": "inspect", "path": "ReplayObserver", "properties": ["seen_projectile", "damage"]})
    check(result.get("properties", {}).get("seen_projectile") == "true", "actual mechanic produced a grenade")
    check(float(result.get("properties", {}).get("damage", "0")) > 0.0, "actual enemy took grenade damage")
    var logs = await command("read_test_log", {"run_id": id, "severity": "error", "raw": true})
    check(logs.get("records", []).is_empty(), "no execution errors in actual gameplay/input branch")
    result = await command("stop_test_game", {"run_id": id})
    check(result.get("state") == "exited" and result.get("stop_method") == "graceful", "one detached process stopped cleanly")
    check(FileAccess.get_sha256(workspace.path_join("grenade.gd")) == source_hash and FileAccess.get_sha256(workspace.path_join("main.gd")) == main_hash, "original grenade and startup source untouched")
    print("REPLAY METRICS: ", JSON.stringify({"duration_ms": Time.get_ticks_msec() - began, "tool_calls": serial, "poll_only_calls": poll_calls, "detached_launches": 1, "mechanic_or_startup_rewrites": 0, "real_provider": false}))
    agent.free()
    runner.free()
    print("REPLAY TESTS: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
