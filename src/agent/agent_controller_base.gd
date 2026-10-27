class_name AgentControllerBase
extends Node

# Lifecycle shared by every coding harness: ownership of the workspace, player
# request recovery, host-bridge dispatch, pending approvals and transcript
# writes. Harness transports (Pi RPC, native CLI sessions) stay in subclasses.

signal status_changed(text: String)
signal assistant_message(text: String)
signal llm_snippet(kind: String, text: String)
signal llm_stream_delta(kind: String, text: String)
signal llm_stream_end(kind: String)
signal transcript_reconciled
signal finished(ok: bool)
signal reload_approval_changed(pending: bool)

const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const GameEditGuardScript = preload("res://src/core/game_edit_guard.gd")

var editor_guard
var game_name := ""
var tools
var metadata = MetadataStoreScript.new()
var transcript = TranscriptStoreScript.new()
var rpc
var busy := false
var last_context_tokens := 0
var last_error := ""
var pending_provider_error := ""
var streamed_text := false
var bridge_dir := ""
var restart_after_finish := false
var operation_id := 0
var pending_reload: Dictionary = {}
var pending_test_commands: Array[Dictionary] = []
var pending_blender_commands: Array[Dictionary] = []
var blender_grants: Dictionary = {}
var auto_compaction_failed_operation := -1

# One recovery budget per player request, after the harness's own retries settle.
const RECOVERY_DELAYS = [8.0, 16.0, 32.0, 64.0]
var recovery_delays: Array = RECOVERY_DELAYS.duplicate()
const RECOVERY_MESSAGE = "Continue work on the original player request below. The previous attempt ended unsuccessfully. Some actions may already have completed, even if the request is absent from native history. Inspect the current state and preserve completed tool results and file edits before repeating any action."
var recovery_generation := 0
var recovery_active := false
var recovery_error := ""
var recovery_attempt := 0
var request_admitted := false
var request_preserved := true
var initialization_failed := false

func configure(p_game_name: String, p_tools) -> void:
    game_name = p_game_name
    if editor_guard == null:
        editor_guard = GameEditGuardScript.new()
    editor_guard.workspace = p_tools.workspace
    tools = p_tools
    tools.blender_enabled = _blender_enabled()
    process_mode = Node.PROCESS_MODE_ALWAYS

func _blender_enabled() -> bool:
    # Metadata predating the option keeps its existing tool surface.
    return bool(metadata.read_game(game_name).get("blender_enabled", true))

func acquire_editor() -> bool:
    if editor_guard == null:
        editor_guard = GameEditGuardScript.new()
        editor_guard.workspace = tools.workspace
    if editor_guard.acquire(): return true
    last_error = editor_guard.error
    status_changed.emit(last_error)
    return false

func send_player_request(text: String) -> void:
    if busy:
        return
    if not acquire_editor():
        assistant_message.emit(last_error)
        finished.emit(false)
        return
    recovery_generation += 1
    var generation = recovery_generation
    recovery_active = true
    recovery_attempt = 0
    var admitted = false
    while generation == recovery_generation:
        recovery_error = ""
        request_admitted = false
        request_preserved = true
        initialization_failed = false
        await _send_player_attempt(_recovery_prompt(text, admitted) if recovery_attempt > 0 else text)
        if generation != recovery_generation:
            return
        admitted = (admitted or request_admitted) if request_preserved else false
        if recovery_error == "":
            recovery_active = false
            return
        # A dead adapter can leave a native backend alive. Retire the tree before
        # waiting/reopening the exact saved session, never replace its history.
        restart_runtime()
        # Abandoned deltas are not durable chat. Rebuild the view before either
        # retry status or the final error; preserve persisted tools and dialogue.
        transcript_reconciled.emit()
        if initialization_failed or recovery_attempt >= recovery_delays.size():
            recovery_active = false
            _fail(recovery_error)
            return
        var delay: float = recovery_delays[recovery_attempt]
        recovery_attempt += 1
        AppLoggerScript.game_event(game_name, "agent.recovery", "attempt=%d delay=%s error=%s" % [recovery_attempt, delay, recovery_error], "WARN")
        status_changed.emit("Turn failed. Retrying in %d seconds (%d/%d)..." % [delay, recovery_attempt, recovery_delays.size()])
        await _wait_recovery(delay, generation)
        if generation != recovery_generation:
            return
        # No await between releasing busy and entering the next attempt.
        busy = false

# Implemented by each harness: performs one native request attempt and settles
# either through request_admitted/request_preserved or through _fail(...).
func _send_player_attempt(_text: String) -> void:
    _fail("This agent controller does not implement player requests.")

# A harness that enforces its own stop condition (for example Pi's turn limit)
# reports it here, so a deliberate abort is not retried as a transient failure.
func _recovery_suppressed() -> bool:
    return false

func _recovery_prompt(objective: String, preserved: bool = true) -> String:
    var context = "" if preserved else "\nNative preservation of this request is unconfirmed."
    return RECOVERY_MESSAGE + context + "\n\nOriginal player request:\n" + objective

func _wait_recovery(seconds: float, generation: int) -> void:
    var deadline = Time.get_ticks_msec() + int(seconds * 1000)
    while generation == recovery_generation and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame

func _record_player_request(text: String) -> void:
    if not recovery_active or recovery_attempt == 0:
        transcript.append(game_name, "user", text)

func cancel() -> void:
    if not busy:
        return
    recovery_generation += 1
    recovery_active = false
    operation_id += 1
    restart_after_finish = false
    AppLoggerScript.game_event(game_name, "pi.cancel", "Cancelled by the player; existing file edits are kept.")
    restart_runtime()
    busy = false
    last_error = ""
    pending_provider_error = ""
    llm_stream_end.emit("assistant")
    llm_stream_end.emit("thinking")
    assistant_message.emit("Cancelled. File edits already made were kept.")
    status_changed.emit("Ready")
    finished.emit(false)

func restart_runtime() -> void:
    if tools != null: tools.cancel_reload()
    if tools != null and is_instance_valid(tools.image_supervisor):
        tools.image_supervisor.stop_all()
    if tools != null and is_instance_valid(tools.blender_supervisor):
        tools.blender_supervisor.stop_all()
    pending_blender_commands.clear()
    blender_grants.clear()
    _clear_pending_reload()
    pending_test_commands.clear()
    if tools != null and is_instance_valid(tools.test_supervisor):
        tools.test_supervisor.stop_all()
    if rpc != null:
        rpc.retire()
    rpc = null
    bridge_dir = ""
    last_context_tokens = 0

func settings_changed() -> void:
    if busy:
        restart_after_finish = true
    else:
        restart_runtime()

func context_tokens() -> int:
    return last_context_tokens

func _exit_tree() -> void:
    restart_runtime()
    if editor_guard != null: editor_guard.release()

func _process(_delta: float) -> void:
    _service_host_bridge()

func _service_host_bridge() -> void:
    if bridge_dir == "":
        return
    _service_pending_test_commands()
    _service_pending_blender_commands()
    var dir = DirAccess.open(bridge_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    var item = dir.get_next()
    var requests: Array[String] = []
    while item != "":
        if not dir.current_is_dir() and item.begins_with("request-") and item.ends_with(".json"):
            requests.append(item)
        item = dir.get_next()
    dir.list_dir_end()
    for file_name in requests:
        var path = bridge_dir.path_join(file_name)
        var claimed = _claim_host_request(path)
        if not bool(claimed.get("ok", false)):
            continue
        var parsed = claimed.get("request", null)
        if typeof(parsed) != TYPE_DICTIONARY:
            continue
        _dispatch_host_request(parsed, bridge_dir)

func _claim_host_request(path: String) -> Dictionary:
    # Moving the request out of the live request namespace is the ownership
    # operation. On Windows this fails while the producer still holds a handle
    # without delete sharing; do not execute the readable request until a later
    # frame can claim it. This also prevents subclasses and the base dispatcher
    # from acting on the same request twice.
    var claimed_path = path + ".claimed-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    if DirAccess.rename_absolute(path, claimed_path) != OK:
        return {"ok": false}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(claimed_path))
    DirAccess.remove_absolute(claimed_path)
    return {"ok": true, "request": parsed}

func _dispatch_host_request(request: Dictionary, directory: String) -> void:
    var command = str(request.get("command", ""))
    var result: Dictionary
    if command in ["reload_game", "add_runtime_child"]:
        if pending_reload.is_empty():
            pending_reload = {"request": request, "bridge_dir": directory, "operation_id": operation_id}
            var setting = "auto_approve_runtime_children" if command == "add_runtime_child" else "auto_approve_reloads"
            if bool(metadata.global_settings().get(setting, false)):
                approve_reload()
                return
            status_changed.emit("Waiting for live child code approval" if command == "add_runtime_child" else "Waiting for reload approval")
            reload_approval_changed.emit(true)
            return
        result = {"ok": false, "error": "Another live code request is already waiting for player approval."}
    elif command == "generate_image":
        result = tools.execute("generate_image", request.get("args", {}))
    elif command in ["blender", "authorize_blender"]:
        if not tools.blender_enabled:
            _write_host_response(directory, request, {"ok": false, "error": "Blender tools are disabled for this game."})
            return
        var args: Dictionary = request.get("args", {}).duplicate(true)
        if command == "authorize_blender":
            if not busy or str(args.get("token", "")) == "" or typeof(args.get("blender_args")) != TYPE_DICTIONARY:
                _write_host_response(directory, request, {"ok": false, "error": "No active Blender authorization operation."})
                return
            args = args.blender_args.duplicate(true)
            if args.get("action") != "start" or str(args.get("script", "")) == "":
                _write_host_response(directory, request, {"ok": false, "error": "Only Python starts need authorization."})
                return
        elif args.has("approval_token"):
            var token = str(args.approval_token)
            args.erase("approval_token")
            var grant: Dictionary = blender_grants.get(token, {})
            blender_grants.erase(token)
            if not busy or grant.get("operation_id", -1) != operation_id or grant.get("bridge_dir") != directory or grant.get("args") != args:
                _write_host_response(directory, request, {"ok": false, "error": "Blender approval is missing, stale, or does not match the script request."})
                return
            _write_host_response(directory, request, tools.execute("blender", {"action": "status", "run_id": grant.run_id}))
            return
        result = tools.execute("blender", args)
        if result.get("state") == "awaiting_approval":
            pending_blender_commands.append({"request": request, "run_id": result.run_id, "bridge_dir": directory, "operation_id": operation_id})
            status_changed.emit("Waiting for Blender Python approval")
            return
        if command == "authorize_blender" and result.has("run_id") and result.get("state") != "cancelled":
            _grant_blender(request, directory, str(result.run_id))
            result = {"ok": true}
    elif command == "remove_runtime_child":
        _runtime_child_request(request, directory, operation_id)
        return
    elif command in ["read_runtime_log", "inspect_runtime", "set_properties"]:
        result = tools.execute(command, request.get("args", {}))
    elif command in ["git_status", "git_diff", "git_log", "git_commit", "delete_path", "move_path"]:
        result = tools.execute(command, request.get("args", {}))
    elif command in ["start_test_game", "read_test_log", "stop_test_game", "test_game_action"]:
        result = tools.execute(command, request.get("args", {}))
        if command == "test_game_action" and result.get("pending", false) and request.get("args", {}).get("action") != "poll":
            pending_test_commands.append({"request": request, "run_id": request.get("args", {}).get("run_id", ""), "command": command, "action_id": result.action_id, "deadline": Time.get_ticks_msec() + 300, "bridge_dir": directory, "operation_id": operation_id})
            return
        if result.get("ok", false) and command == "stop_test_game" and result.get("state", "") != "exited":
            pending_test_commands.append({"request": request, "run_id": request.get("args", {}).get("run_id", ""), "command": command, "bridge_dir": directory, "operation_id": operation_id})
            return
    elif command == "diagnostic_notice":
        result = tools.runner.runtime_log.prepare_notification() if tools != null and tools.runner != null else {"ok": true, "notice": ""}
    elif command == "provider_retry":
        var retry_args: Dictionary = request.get("args", {})
        AppLoggerScript.game_event(game_name, "pi.retry", JSON.stringify(retry_args), "WARN")
        status_changed.emit("Provider response was empty; retrying %d/%d…" % [int(retry_args.get("attempt", 0)), int(retry_args.get("maxRetries", 3))])
        result = {"ok": true}
    elif command == "compaction_status":
        result = {"ok": true, "blocked": auto_compaction_failed_operation == operation_id}
    elif command == "diagnostic_delivery":
        tools.runner.runtime_log.commit_delivery(str(request.get("args", {}).get("delivery_id", "")))
        result = {"ok": true}
    else:
        result = {"ok": false, "error": "Unknown GameSmith host bridge command: " + command}
    _write_host_response(directory, request, result)

func _runtime_child_request(request: Dictionary, directory: String, operation: int) -> void:
    var result: Dictionary = await tools.wait_reload(tools.execute(str(request.command), request.get("args", {})))
    if operation == operation_id and directory == bridge_dir:
        _write_host_response(directory, request, result)

func _grant_blender(request: Dictionary, directory: String, run_id: String) -> void:
    var auth: Dictionary = request.args
    blender_grants[str(auth.token)] = {"operation_id": operation_id, "bridge_dir": directory, "run_id": run_id, "args": auth.blender_args.duplicate(true)}

func _service_pending_blender_commands() -> void:
    for pending in pending_blender_commands.duplicate():
        if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir:
            if tools != null and is_instance_valid(tools.blender_supervisor):
                tools.blender_supervisor.stop_all()
            pending_blender_commands.erase(pending)
            continue
        var result: Dictionary = tools.execute("blender", {"action": "status", "run_id": pending.run_id})
        if result.get("state") != "awaiting_approval":
            pending_blender_commands.erase(pending)
            if pending.request.get("command") == "authorize_blender" and result.get("state") != "cancelled":
                _grant_blender(pending.request, pending.bridge_dir, str(pending.run_id))
                # Authorization succeeded even if the approved job already failed.
                # The actual MCP call must receive its execution diagnostics.
                result = {"ok": true}
            _write_host_response(pending.bridge_dir, pending.request, result)
            status_changed.emit("Agent is working...")

func _service_pending_test_commands() -> void:
    for pending in pending_test_commands.duplicate():
        if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir:
            pending_test_commands.erase(pending)
            continue
        var state: Dictionary = tools.tests().status(pending.run_id)
        var result: Dictionary = {}
        if pending.command == "stop_test_game" and state.get("state") == "exited":
            result = tools.execute("stop_test_game", {"run_id": pending.run_id})
        if pending.command == "test_game_action":
            var polled = tools.tests().request_action(pending.run_id, {"action": "poll", "action_id": pending.action_id})
            if not polled.get("pending", false) or Time.get_ticks_msec() >= pending.deadline:
                result = polled
        if not result.is_empty():
            pending_test_commands.erase(pending)
            _write_host_response(bridge_dir, pending.request, result)

func approve_reload() -> void:
    if pending_reload.is_empty():
        return
    var pending = pending_reload
    _clear_pending_reload()
    if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir or bridge_dir == "":
        return
    if pending.request.command == "add_runtime_child":
        status_changed.emit("Testing and adding live child code...")
        await _runtime_child_request(pending.request, pending.bridge_dir, pending.operation_id)
        return
    status_changed.emit("Reloading game...")
    var result: Dictionary = await tools.wait_reload(tools.reload_game(func(): return pending.operation_id != operation_id or pending.bridge_dir != bridge_dir))
    if pending.operation_id != operation_id or pending.bridge_dir != bridge_dir: return
    _write_host_response(bridge_dir, pending.request, result)
    status_changed.emit("Pi is working...")

func _clear_pending_reload() -> void:
    if not pending_reload.is_empty():
        pending_reload = {}
        reload_approval_changed.emit(false)

func _write_host_response(directory: String, request: Dictionary, result: Dictionary) -> void:
    var response_path = directory.path_join("response-%s.json" % str(request.get("id", "")))
    var tmp = response_path + ".tmp"
    var out = FileAccess.open(tmp, FileAccess.WRITE)
    if out != null:
        out.store_string(preload("res://src/core/json_output.gd").stringify(result))
        out.close()
        DirAccess.rename_absolute(tmp, response_path)

func _fail(message: String) -> void:
    if tools != null: tools.cancel_reload()
    if recovery_active and not _recovery_suppressed():
        recovery_error = message
        last_error = message
        busy = true
        return
    blender_grants.clear()
    if not pending_blender_commands.is_empty():
        if tools != null and is_instance_valid(tools.blender_supervisor): tools.blender_supervisor.stop_all()
        pending_blender_commands.clear()
    _clear_pending_reload()
    AppLoggerScript.game_event(game_name, "pi.failed", message, "ERROR")
    transcript.append(game_name, "assistant", "Error: " + message)
    assistant_message.emit("Error: " + message)
    status_changed.emit("Ready")
    busy = false
    if restart_after_finish:
        restart_after_finish = false
        restart_runtime()
    finished.emit(false)
