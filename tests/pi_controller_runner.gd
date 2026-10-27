extends SceneTree

# Pi request completion is a transport concern: the shared recovery loop and the
# host bridge are covered by turn_recovery_runner.gd.

const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")

var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if not value: failures += 1

func run() -> void:
    _test_request_has_no_host_deadline_or_fake_completion()
    await _test_stale_settlement_does_not_finish_next_request()
    quit(1 if failures else 0)

func _test_request_has_no_host_deadline_or_fake_completion() -> void:
    var source = FileAccess.get_file_as_string("res://src/agent/pi_agent_controller.gd")
    check(not "20 * 60 * 1000" in source and not "20 minute host deadline" in source, "Pi requests have no arbitrary host wall-clock deadline")
    check(not 'final_text = "Done."' in source, "GameSmith never invents a fake assistant completion message")
    var rpc_source = FileAccess.get_file_as_string("res://src/pi/pi_rpc_session.gd")
    check(not "timeout_sec" in rpc_source and not "Timed out waiting for Pi RPC response" in rpc_source, "Pi RPC commands wait for a response or process exit instead of an artificial timeout")
    var extension_source = FileAccess.get_file_as_string("res://tools/pi/gamesmith-extension.ts")
    check(not "Timed out waiting for GameSmith host tool" in extension_source and not "Date.now() + 60_000" in extension_source, "GameSmith Pi host tools wait for completion or abort instead of an artificial timeout")

func _test_stale_settlement_does_not_finish_next_request() -> void:
    var agent = PiAgentControllerScript.new()
    root.add_child(agent)
    agent.busy = true
    agent.turn_count = 0
    agent._on_pi_record({"type": "agent_settled"})
    check(not agent.has_meta("_pi_settled"), "settlement from a previous aborted run cannot settle a new request before its first Pi turn")
    agent._on_pi_record({"type": "turn_start"})
    agent._on_pi_record({"type": "agent_settled"})
    check(agent.has_meta("_pi_settled"), "settlement is accepted after the current request has actually started a Pi turn")
    agent.queue_free()
    await process_frame
