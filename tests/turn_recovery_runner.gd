extends SceneTree

var failures := 0

class MemoryTranscript extends RefCounted:
    var rows: Array = []
    func append(_game: String, role: String, text: String) -> void:
        rows.append({"role": role, "content": text})
    func read_all(_game: String) -> Array:
        return rows

class FakeRpc extends Node:
    var running := true
    var owner_agent
    func command(request: Dictionary) -> Dictionary:
        if request.type == "cancel": return {"success": true}
        owner_agent.prompts.append(request.message)
        await get_tree().process_frame
        if owner_agent.reject:
            return {"success": false, "error": "fixture admission failure", "initialization_failed": owner_agent.initialization_failure}
        if owner_agent.crash:
            running = false
            return {"success": true}
        var ok: bool = owner_agent.prompts.size() > owner_agent.failures_before_success
        if owner_agent.stream:
            owner_agent._on_command_record({"type": "delta", "kind": "assistant", "text": "done" if ok else "wrong partial"})
        owner_agent._on_command_record({"type": "complete", "ok": ok, "text": ("" if owner_agent.empty_answer else "done") if ok else "partial", "error": "" if ok else "fixture failed", "initialization_failed": not ok and owner_agent.initialization_failure})
        return {"success": true}
    func retire() -> void:
        running = false
        queue_free()

class Agent extends "res://src/agent/opencode_agent_controller.gd":
    var prompts: Array = []
    var failures_before_success := 0
    var reject := false
    var crash := false
    var empty_answer := false
    var stream := false
    var initialization_failure := false
    var startup_failure := false
    var restarts := 0
    var waits: Array = []
    var completions: Array = []
    var notices: Array = []
    func acquire_editor() -> bool: return true
    func _start_command_runtime() -> Dictionary:
        if startup_failure: return {"ok": false, "error": "fixture unavailable executable"}
        if rpc == null or not rpc.running:
            rpc = FakeRpc.new()
            rpc.owner_agent = self
            add_child(rpc)
        return {"ok": true}
    func _maybe_auto_compact(_phase: String) -> void: pass
    func restart_runtime() -> void:
        restarts += 1
        super.restart_runtime()
    func _wait_recovery(seconds: float, generation: int) -> void:
        waits.append(seconds)
        await super._wait_recovery(0.02, generation)

class FakePiRpc extends Node:
    var running := true
    var owner_agent
    func command(request: Dictionary) -> Dictionary:
        if request.type == "get_last_assistant_text": return {"success": true, "data": {"text": "Pi done"}}
        owner_agent.prompts.append(request.message)
        await get_tree().process_frame
        if owner_agent.reject:
            return {"success": false, "error": "fixture Pi initialization failure", "initialization_failed": true}
        owner_agent._on_pi_record({"type": "turn_start"})
        owner_agent._on_pi_record({"type": "message_end", "message": {"role": "assistant", "content": [], "stopReason": "length" if owner_agent.prompts.size() == 1 else "stop"}})
        owner_agent._on_pi_record({"type": "agent_settled"})
        return {"success": true}
    func retire() -> void:
        running = false
        queue_free()

class PiAgent extends "res://src/agent/pi_agent_controller.gd":
    var prompts: Array = []
    var reject := false
    var startup_failure := false
    var waits: Array = []
    func acquire_editor() -> bool: return true
    func _ensure_runtime() -> Dictionary:
        if startup_failure: return {"ok": false, "error": "fixture Pi configuration failure"}
        if rpc == null:
            rpc = FakePiRpc.new()
            rpc.owner_agent = self
            add_child(rpc)
        return {"ok": true}
    func _maybe_auto_compact(_phase: String) -> void: pass
    func _refresh_context_usage() -> bool: return true
    func _wait_recovery(_seconds: float, generation: int) -> void:
        waits.append(_seconds)
        await super._wait_recovery(0.02, generation)

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value: failures += 1
func agent() -> Agent:
    var a = Agent.new()
    a.game_name = "Recovery fixture"
    a.transcript = MemoryTranscript.new()
    root.add_child(a)
    a.finished.connect(func(ok): a.completions.append(ok))
    a.assistant_message.connect(func(text): a.notices.append(text))
    return a
func idle(a) -> void:
    var deadline = Time.get_ticks_msec() + 5000
    while a.busy and Time.get_ticks_msec() < deadline: await process_frame
    check(not a.busy, "request settles within fixture deadline")
func run() -> void:
    var a = agent()
    a.failures_before_success = 2
    a.send_player_request("build once")
    await idle(a)
    check(a.prompts.size() == 3 and a.waits == [8.0, 16.0], "failed turns back off then succeed")
    check(a.prompts.size() == 3 and a.prompts[1] != "build once" and "continu" in a.prompts[1].to_lower(), "accepted task continues rather than replaying original request")
    check(a.transcript.rows.size() == 2 and a.transcript.rows[0].content == "build once" and a.transcript.rows[1].content == "done", "transcript contains one player request and final answer")
    check(a.completions == [true] and a.notices == ["done"], "intermediate failures do not finish or show raw error messages")
    check(a.restarts == 2, "failed backend is retired before each recovery")
    a.queue_free()
    await process_frame
    a = agent()
    a.empty_answer = true
    a.send_player_request("successful turn without prose")
    await idle(a)
    check(a.prompts.size() == 1 and a.waits.is_empty() and a.completions == [true], "successful native completion without prose never retries")
    a.queue_free()
    await process_frame
    a = agent()
    a.failures_before_success = 99
    a.send_player_request("always fail")
    await idle(a)
    check(a.prompts.size() == 5 and a.waits == [8.0, 16.0, 32.0, 64.0], "exactly four retries with requested backoff")
    check(a.completions == [false] and a.notices.size() == 1, "exhaustion reports one final failure")
    a.queue_free()
    await process_frame
    a = agent()
    a.reject = true
    a.send_player_request("not admitted")
    await idle(a)
    check(a.prompts.size() == 5 and a.prompts.all(func(p): return p == "not admitted"), "unaccepted requests retain original objective")
    a.queue_free()
    await process_frame
    a = agent()
    a.crash = true
    a.send_player_request("crash")
    await idle(a)
    check(a.prompts.size() == 5 and a.restarts >= 4, "adapter death follows bounded recovery")
    a.queue_free()
    await process_frame
    a = agent()
    a.failures_before_success = 99
    a.send_player_request("stop during backoff")
    while a.waits.is_empty(): await process_frame
    a.cancel()
    await idle(a)
    await create_timer(0.08).timeout
    check(a.prompts.size() == 1 and a.completions == [false], "Stop during backoff prevents subsequent attempts")
    a.failures_before_success = 0
    a.send_player_request("new task")
    await idle(a)
    check(a.prompts.size() == 2 and a.prompts[1] == "new task", "fresh request works after cancelled recovery")
    a.queue_free()
    await process_frame
    a = agent()
    a.failures_before_success = 1
    a.stream = true
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.current_game = a.game_name
    app.transcript = a.transcript
    a.transcript.append(a.game_name, "tool", "completed edit")
    a.llm_stream_delta.connect(app._append_stream_delta)
    a.llm_stream_end.connect(app._end_stream_block)
    if a.has_signal("transcript_reconciled"):
        a.connect("transcript_reconciled", app._load_transcript)
    var observed: Array = []
    a.status_changed.connect(func(text):
        if text.begins_with("Turn failed."):
            observed.append(app.transcript_view.get_parsed_text())
    )
    a.send_player_request("recover streamed answer")
    await idle(a)
    check(observed.size() == 1 and not "wrong partial" in observed[0], "abandoned stream is removed before retry status")
    var visible: String = app.transcript_view.get_parsed_text()
    check(not "wrong partial" in visible and "done" in visible, "visible chat contains recovered answer without failed partial")
    check("completed edit" in visible and "recover streamed answer" in visible, "reconciliation preserves durable tools and player request")
    app._load_transcript()
    check(app.transcript_view.get_parsed_text() == visible, "live recovered chat matches reopened transcript")
    app.queue_free()
    a.queue_free()
    await process_frame
    for phase in ["admission", "completion", "startup"]:
        a = agent()
        a.initialization_failure = true
        a.reject = phase == "admission"
        a.startup_failure = phase == "startup"
        a.failures_before_success = 99
        a.send_player_request("broken initialization")
        await idle(a)
        check(a.waits.is_empty() and a.prompts.size() == (0 if phase == "startup" else 1), phase + " initialization failure never retries")
        check(a.completions == [false] and a.notices.size() == 1 and a.last_error != "", phase + " initialization failure immediately reports actionable error")
        check(a.rpc == null and not a.busy, phase + " initialization failure retires backend and releases controls")
        a.initialization_failure = false
        a.reject = false
        a.startup_failure = false
        a.failures_before_success = 0
        a.send_player_request("manual retry")
        await idle(a)
        check(a.last_error == "" and a.completions == [false, true], phase + " initialization can be retried manually")
        a.queue_free()
        await process_frame
    var pi_agent = PiAgent.new()
    pi_agent.game_name = "Pi recovery"
    pi_agent.transcript = MemoryTranscript.new()
    root.add_child(pi_agent)
    pi_agent.send_player_request("Pi task")
    await idle(pi_agent)
    check(pi_agent.last_error == "" and pi_agent.prompts.size() == 2 and pi_agent.prompts[1] == pi_agent.RECOVERY_MESSAGE, "Pi generation limit uses shared continuation recovery")
    check(pi_agent.transcript.rows.size() == 2, "Pi recovery records only player request and final answer")
    pi_agent.queue_free()
    await process_frame
    for phase in ["startup", "admission"]:
        pi_agent = PiAgent.new()
        pi_agent.game_name = "Pi initialization fixture"
        pi_agent.transcript = MemoryTranscript.new()
        pi_agent.reject = phase == "admission"
        pi_agent.startup_failure = phase == "startup"
        root.add_child(pi_agent)
        pi_agent.send_player_request("Pi configuration error")
        await idle(pi_agent)
        check(pi_agent.waits.is_empty() and pi_agent.last_error != "" and pi_agent.rpc == null, "Pi " + phase + " initialization reports immediately without retry")
        pi_agent.queue_free()
        await process_frame
    quit(1 if failures else 0)
