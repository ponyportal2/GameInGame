extends SceneTree

# Exercise the production request loop and record handler. Real IPC, native
# recovery and provider cancellation remain covered by their existing suites.
class MemoryTranscript extends RefCounted:
    var rows: Array = []
    func append(_game: String, role: String, text: String) -> void:
        rows.append({"role": role, "content": text})

class FixtureRpc extends Node:
    var running := true
    var held := false
    var released := false
    var retire_on_cancel := true
    var accepted: Dictionary = {"success": true}
    var records: Array = []
    var compact_calls := 0
    var owner_agent
    func command(request: Dictionary) -> Dictionary:
        if request.type == "cancel": return {"success": true}
        if request.type == "compact":
            compact_calls += 1
            return {"success": true}
        while held and not released: await get_tree().process_frame
        for record in records: owner_agent._on_command_record(record)
        return accepted
    func retire() -> void:
        if retire_on_cancel: running = false

class Agent extends "res://src/agent/native_agent_controller.gd":
    var next_rpc
    func acquire_editor() -> bool: return true
    func _start_command_runtime() -> Dictionary:
        rpc = next_rpc
        return {"ok": true}
    func _harness_name() -> String: return "Fixture"

class MissingRuntime extends "res://src/agent/native_agent_controller.gd":
    func acquire_editor() -> bool: return true

class OpenCodeAgent extends "res://src/agent/opencode_agent_controller.gd":
    var next_rpc
    func acquire_editor() -> bool: return true
    func _start_command_runtime() -> Dictionary:
        rpc = next_rpc
        return {"ok": true}

var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if not value: failures += 1

func agent(script = Agent):
    var a = script.new()
    a.game_name = "Native lifecycle contract"
    a.transcript = MemoryTranscript.new()
    root.add_child(a)
    return a

func transport(a, records: Array = []) -> FixtureRpc:
    var r = FixtureRpc.new()
    r.owner_agent = a
    r.records = records
    a.add_child(r)
    a.next_rpc = r
    return r

func run() -> void:
    var native_base = load("res://src/agent/native_agent_controller.gd")
    for provider in ["command_code", "opencode"]:
        var controller = load("res://src/agent/" + provider + "_agent_controller.gd")
        check(controller.get_base_script() == native_base, provider + " directly extends the shared native lifecycle")
    var a = agent()
    var rpc = transport(a)
    rpc.accepted = {"success": false, "error": "admission rejected", "request_preserved": false, "initialization_failed": true, "runtime_failed": true}
    var finishes: Array = []
    a.finished.connect(func(ok): finishes.append(ok))
    await a._send_player_attempt("original objective")
    check(not a.request_admitted and not a.request_preserved and a.initialization_failed, "admission rejection preserves initialization and history flags")
    check(a.last_error == "admission rejected" and finishes == [false] and not a.busy and a.rpc == null, "native admission failure remains observable and retires failed runtime")
    check(a.transcript.rows[0] == {"role": "user", "content": "original objective"}, "admission failure records the original objective")
    a.free()

    for corrected in [false, true]:
        a = agent()
        var events: Array = []
        a.llm_stream_delta.connect(func(kind, text): events.append(["delta", kind, text]))
        a.transcript_reconciled.connect(func(): events.append(["reconciled"]))
        a.assistant_message.connect(func(text): events.append(["message", text]))
        a.finished.connect(func(ok): events.append(["finished", ok, a.transcript.rows.duplicate(true)]))
        transport(a, [{"type": "backend", "pid": 4321}, {"type": "context", "tokens": 123}, {"type": "delta", "kind": "assistant", "text": "streamed"}, {"type": "complete", "ok": true, "corrected": corrected, "text": "canonical"}])
        await a._send_player_attempt("build")
        check(a.backend_pid == 4321 and a.last_context_tokens == 123 and a.last_error == "", "native backend and context records survive extraction")
        check(a.transcript.rows == [{"role": "user", "content": "build"}, {"role": "assistant", "content": "canonical"}], "streamed completion persists canonical text exactly once")
        check(events.has(["delta", "assistant", "streamed"]) and not events.has(["message", "canonical"]), "streamed completion does not duplicate the assistant message")
        check(events.has(["reconciled"]) == corrected and events[-1] == ["finished", true, a.transcript.rows], "correction reconciles before success after transcript persistence")
        a.free()

    a = agent()
    transport(a, [{"type": "complete", "ok": false, "error": "native completion failed", "request_preserved": false, "initialization_failed": true}])
    await a._send_player_attempt("fail")
    check(a.last_error == "native completion failed" and not a.request_preserved and a.initialization_failed, "failed completion preserves last_error and native preservation flags")
    a.free()

    a = agent()
    var first = transport(a)
    first.held = true
    first.accepted = {"success": false, "error": "old admission failure", "request_preserved": false}
    var completions: Array = []
    a.finished.connect(func(ok): completions.append(ok))
    a._send_player_attempt("old request")
    a.cancel()
    check(completions == [false] and not a.busy and not first.running, "base cancellation retires the old attempt")
    var second = transport(a, [{"type": "complete", "ok": true, "text": "new answer"}])
    second.held = true
    a._send_player_attempt("new request")
    first.released = true
    await process_frame
    await process_frame
    check(a.busy and a.rpc == second and a.last_error == "" and a.request_preserved and completions == [false], "old admission response cannot change or complete the replacement attempt")
    second.released = true
    await process_frame
    await process_frame
    check(not a.busy and completions == [false, true] and a.transcript.rows[-1].content == "new answer", "replacement attempt completes with its own answer")
    a.free()

    a = agent()
    rpc = transport(a)
    a.rpc = rpc
    a.bridge_dir = "native-settings-bridge"
    a.last_context_tokens = 876
    for active in [false, true]:
        a.busy = active
        a.settings_changed()
        check(a.rpc == rpc and rpc.running and a.bridge_dir == "native-settings-bridge" and a.last_context_tokens == 876 and not a.restart_after_finish, "native settings changes preserve the existing runtime, busy=" + str(active))
    var statuses: Array = []
    a.status_changed.connect(func(text): statuses.append(text))
    a.approve_reload()
    check(statuses.size() == 1 and statuses[0].begins_with("Fixture is working"), "native approval wrapper retains provider status feedback")
    a.free()

    a = agent(MissingRuntime)
    await a._send_player_attempt("must not launch Command-code")
    check(a.initialization_failed and a.rpc == null and "does not implement runtime construction" in a.last_error, "native base fails explicitly without a concrete runtime constructor")
    a.free()

    a = agent(OpenCodeAgent)
    var original = a.metadata.global_settings()
    var settings = original.duplicate(true)
    settings.compaction_auto_tokens = 1
    a.metadata.save_global_settings(settings)
    a.last_context_tokens = 100000
    rpc = transport(a, [{"type": "complete", "ok": true, "text": "done"}])
    await a._send_player_attempt("native compaction remains native")
    check(rpc.compact_calls == 0 and a.last_error == "", "OpenCode never performs host-driven automatic compaction above the threshold")
    check(not a.compact_now().get("ok", true), "OpenCode retains its manual compaction rejection")
    a.metadata.save_global_settings(original)
    a.free()
    quit(1 if failures else 0)
