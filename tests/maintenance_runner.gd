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
    print("MAINTENANCE TESTS: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
