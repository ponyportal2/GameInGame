extends SceneTree

var passed := 0
var failed := 0

class FakeRpc extends Node:
    var running := true
    var compactions := 0
    var fail_compaction := false
    var fail_stats := false
    var owner_agent
    var stayed_busy := true
    func command(request: Dictionary) -> Dictionary:
        await get_tree().process_frame
        if request.type == "compact":
            compactions += 1
            return {"success": false, "error": "test failure"} if fail_compaction else {"success": true, "data": {"summary": "summary", "tokensBefore": 7000}}
        if request.type == "get_session_stats":
            stayed_busy = stayed_busy and owner_agent.busy
            return {"success": false} if fail_stats else {"success": true, "data": {"contextUsage": {"tokens": 7000}}}
        return {"success": true}
    func retire() -> void:
        running = false

class Agent extends PiAgentController:
    func _ensure_runtime() -> Dictionary:
        return {"ok": true}

func check(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var agent = Agent.new()
    root.add_child(agent)
    agent.game_name = "MaintenanceTests"
    var rpc = FakeRpc.new()
    agent.add_child(rpc)
    agent.rpc = rpc
    rpc.owner_agent = agent
    rpc.fail_stats = true
    var result = await agent.compact_now()
    check(result.ok and result.tokens_after == null, "Missing checkpoint stats remain unknown rather than zero")
    check(rpc.stayed_busy and not agent.busy, "Manual compaction owns UI through checkpoint stats")
    rpc.fail_stats = false
    rpc.fail_compaction = true
    agent.metadata.save_global_settings({"compaction_auto_tokens": 1000})
    agent.busy = true
    agent.operation_id += 1
    var before = rpc.compactions
    await agent._maybe_auto_compact("before_request")
    await agent._maybe_auto_compact("after_turn")
    check(rpc.compactions == before + 1, "Automatic failure retried at most once per player request")
    agent.operation_id += 1
    await agent._maybe_auto_compact("before_request")
    check(rpc.compactions == before + 2, "Next player request may retry automatic compaction")
    agent.busy = false
    agent.free()
    test_interrupted_runs()
    print("MAINTENANCE TESTS: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)

func test_interrupted_runs() -> void:
    var supervisor = preload("res://src/core/test_game_supervisor.gd").new()
    root.add_child(supervisor)
    supervisor.rebind("user://games/TerminalStateTests")
    var evidence = preload("res://src/core/test_evidence.gd")
    var test_root: String = supervisor._test_root()
    var lost_path = test_root.path_join("lost")
    JsonStore.write_dict(lost_path.path_join("config.json"), {"run_id": "lost", "parent_token": "old", "mode": "headless"})
    JsonStore.write_dict(lost_path.path_join("outcome.json"), {"ok": true, "run_id": "lost", "state": "running", "action_id": "pending-action", "pid": OS.get_process_id()})
    evidence.recover(test_root)
    var result = supervisor.request_action("lost", {"action": "poll", "action_id": "pending-action"})
    check(not result.get("ok", false) and not result.get("pending", false) and result.get("process", {}).get("state") == "interrupted", "Recovered action fails explicitly when ownership is lost")
    var live_path = test_root.path_join("live")
    JsonStore.write_dict(live_path.path_join("outcome.json"), {"run_id": "live", "state": "running"})
    var retained = evidence.enforce(test_root, ["live"], 1)
    check(not DirAccess.dir_exists_absolute(lost_path) and retained.get("expired", []).any(func(entry): return entry.run_id == "lost"), "Interrupted evidence expires with explicit retention metadata")
    check(DirAccess.dir_exists_absolute(live_path), "Retention preserves active evidence while deleting interrupted runs")
    supervisor.free()
