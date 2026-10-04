extends SceneTree

var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func _init() -> void:
    call_deferred("run")

func fixture(name: String, source: String) -> String:
    var path = "user://games/" + name
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
    var file = FileAccess.open(path.path_join("main.gd"), FileAccess.WRITE)
    file.store_string(source)
    file.close()
    return path

func wait_for(supervisor, id: String, predicate: Callable, seconds: float = 12.0) -> Dictionary:
    var deadline = Time.get_ticks_msec() + int(seconds * 1000)
    var result: Dictionary = supervisor.status(id)
    while not predicate.call(result) and Time.get_ticks_msec() < deadline:
        await create_timer(0.05).timeout
        result = supervisor.status(id)
    return result

func run() -> void:
    if not ResourceLoader.exists("res://src/core/test_game_supervisor.gd"):
        check(false, "Separate test-process supervisor exists")
        print("TEST PROCESS TESTS: ", passed, " passed, ", failed, " failed")
        quit(1)
        return
    var supervisor = load("res://src/core/test_game_supervisor.gd").new()
    root.add_child(supervisor)
    supervisor.grace_ms = 5000
    var workspace = fixture("ProcessTests", "extends Node\nfunc window_state():\n\treturn str(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS)) + ':' + str(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)\nvar ticks = 0\nvar pressed = false\nfunc echo(value):\n\treturn value\nfunc _input(event):\n\tif event.is_action('test_fire'):\n\t\tpressed = event.is_pressed()\nfunc _ready():\n\tvar color = ColorRect.new()\n\tcolor.color = Color.RED\n\tcolor.size = Vector2(100, 100)\n\tadd_child(color)\n\tInputMap.add_action('test_fire')\n\tprint('TEST_CHILD_READY')\n\tvar f = FileAccess.open('user://test-save.txt', FileAccess.WRITE)\n\tf.store_string('isolated')\nfunc _process(_delta):\n\tticks += 1\n")
    check(not supervisor.start(workspace, "rendered").ok, "Rendered testing denied by default")
    check(not supervisor.start(workspace, "bogus").ok, "Unknown mode rejected")
    var settings = MetadataStore.new()
    settings.save_global_settings({"allow_rendered_tests": true})
    check(supervisor.rendered_allowed(), "Rendered permission read from current settings")
    settings.save_global_settings({"allow_rendered_tests": false})
    check(not supervisor.rendered_allowed(), "Permission revocation takes effect without prompt rebuild")
    var started: Dictionary = supervisor.start(workspace, "headless")
    check(started.ok and started.mode == "headless", "Headless starts despite rendered permission being off")
    var id: String = started.run_id
    var running = await wait_for(supervisor, id, func(s): return s.get("state") == "running")
    check(running.state == "running", "Child uses production loader and reaches running state")
    check(running.pid != OS.get_process_id(), "Game executes in a separate process")
    check(not supervisor.start(workspace, "headless").ok, "Concurrent test processes are bounded")
    check(not FileAccess.file_exists("user://test-save.txt"), "Test saves do not write into player user data")
    check(FileAccess.file_exists(running.user_data.path_join("test-save.txt")), "Test has separate writable user data")
    var logs: Dictionary = supervisor.read_log(id, {"raw": true})
    check(logs.ok and str(logs).contains("TEST_CHILD_READY"), "Shared diagnostics capture child output")
    check(logs.session_id != "" and logs.mode == "headless", "Logs identify test session and mode")
    supervisor.request_action(id, {"action": "inspect"})
    var inspected = await wait_for(supervisor, id, func(s): return s.has("action_result"))
    check(inspected.get("action_result", {}).get("ok", false), "Agent can inspect the separate game")
    supervisor.request_action(id, {"action": "inspect", "properties": ["ticks"]})
    inspected = await wait_for(supervisor, id, func(s): return s.has("action_result"))
    check(int(inspected.get("action_result", {}).get("properties", {}).get("ticks", "0")) > 0, "Separate game advances while host services actions")
    supervisor.request_action(id, {"action": "call", "method": "echo", "arguments": [42]})
    inspected = await wait_for(supervisor, id, func(s): return s.has("action_result"))
    check(float(inspected.get("action_result", {}).get("value", "0")) == 42.0, "Agent can invoke a game test method")
    supervisor.request_action(id, {"action": "input", "input_action": "test_fire", "pressed": true})
    await wait_for(supervisor, id, func(s): return s.has("action_result"))
    supervisor.request_action(id, {"action": "inspect", "properties": ["pressed"]})
    inspected = await wait_for(supervisor, id, func(s): return s.has("action_result"))
    check(inspected.get("action_result", {}).get("properties", {}).get("pressed") == "true", "Agent input reaches the separate game")
    supervisor.request_action(id, {"action": "screenshot"})
    inspected = await wait_for(supervisor, id, func(s): return s.has("action_result"))
    check(not inspected.get("action_result", {}).get("ok", true), "Headless screenshot gives explicit unsupported result")
    supervisor.request_stop(id)
    var stopped = await wait_for(supervisor, id, func(s): return s.state == "exited")
    check(stopped.state == "exited" and stopped.stop_method == "graceful", "Normal stop exits cleanly")
    check(stopped.exit_code == 0, "Clean exit code is reported")
    check(supervisor.request_stop(id).get("ok", false), "Repeated stop is idempotent")
    var reopened = load("res://src/core/test_game_supervisor.gd").new()
    root.add_child(reopened)
    reopened.rebind(workspace)
    check(str(reopened.read_log(id, {})).contains("TEST_CHILD_READY"), "Completed test evidence survives supervisor reopening")
    check(reopened.read_log("", {}).runs.size() > 0, "Recent test runs can be discovered after reopening")
    reopened.queue_free()
    settings.save_global_settings({"allow_rendered_tests": true})
    started = supervisor.start(workspace, "rendered")
    check(started.ok, "Rendered testing starts after explicit permission")
    running = await wait_for(supervisor, started.run_id, func(s): return s.state == "running")
    check(running.state == "running" and running.mode == "rendered", "Rendered child reaches running state")
    supervisor.request_action(started.run_id, {"action": "call", "method": "window_state"})
    inspected = await wait_for(supervisor, started.run_id, func(s): return s.has("action_result"))
    check(inspected.get("action_result", {}).get("value") == "true:true", "Rendered test window is unfocusable and minimized")
    supervisor.request_action(started.run_id, {"action": "screenshot"})
    inspected = await wait_for(supervisor, started.run_id, func(s): return s.has("action_result"))
    var screenshot: Dictionary = inspected.get("action_result", {})
    check(screenshot.get("ok", false) and Marshalls.base64_to_raw(screenshot.get("image_base64", "")).size() > 8, "Rendered child returns a real screenshot")
    var image = Image.new()
    var png = Marshalls.base64_to_raw(screenshot.get("image_base64", ""))
    check(image.load_png_from_buffer(png) == OK and image.get_pixel(10, 10).r > 0.8, "Minimized screenshot captures game drawing")
    supervisor.request_action(started.run_id, {"action": "call", "method": "window_state"})
    inspected = await wait_for(supervisor, started.run_id, func(s): return s.has("action_result"))
    check(inspected.get("action_result", {}).get("value") == "true:true", "Screenshot does not restore or focus the test window: " + str(inspected.get("action_result", {}).get("value")))
    supervisor.request_stop(started.run_id)
    await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    settings.save_global_settings({"allow_rendered_tests": false})
    workspace = fixture("ProcessBroken", "extends Node\nfunc _ready():\n\tvar missing = null\n\tmissing.nope()\n")
    started = supervisor.start(workspace, "headless")
    stopped = await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    check(stopped.exit_code != 0, "Startup runtime error fails standalone load")
    check(str(supervisor.read_log(started.run_id, {})).contains("nope"), "Startup error evidence remains readable after exit")
    workspace = fixture("ProcessQuit", "extends Node\nfunc _ready():\n\tget_tree().quit(88)\n")
    started = supervisor.start(workspace, "headless")
    stopped = await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    check(stopped.exit_code == 88, "Generated quit affects only child and preserves its exit code")
    workspace = fixture("ProcessHang", "extends Node\nfunc _ready():\n\twhile true:\n\t\tpass\n")
    supervisor.grace_ms = 250
    started = supervisor.start(workspace, "headless")
    await create_timer(0.5).timeout
    supervisor.request_stop(started.run_id)
    stopped = await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    check(stopped.stop_method == "forced", "Unresponsive child is killed after grace period")
    check(str(stopped.get("stop_reason", "")).contains("graceful"), "Forced stop explains failed graceful shutdown to agent")
    check(str(supervisor.read_log(started.run_id, {})).contains("forced"), "Supervisor preserves forced shutdown evidence")
    check(not supervisor.status("../escape").ok, "Unknown run IDs cannot access arbitrary files")
    await test_maintenance()
    await test_bridge_and_prompt()
    supervisor.queue_free()
    await process_frame
    print("TEST PROCESS TESTS: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)

func test_maintenance() -> void:
    var supervisor = load("res://src/core/test_game_supervisor.gd").new()
    root.add_child(supervisor)
    var workspace = fixture("ProcessMaintenance", "extends Node\nfunc hang():\n\twhile true:\n\t\tpass\n")
    var started = supervisor.start(workspace)
    var id: String = started.run_id
    await wait_for(supervisor, id, func(s): return s.state == "running")
    var action = supervisor.request_action(id, {"action": "call", "method": "hang"})
    check(action.get("pending", false) and action.get("action_id", "") != "", "Hung action returns an identity immediately")
    await create_timer(0.3).timeout
    check(supervisor.request_action(id, {"action": "poll", "action_id": action.get("action_id")}).get("pending", false), "Hung action polling returns without blocking")
    check(not supervisor.request_action(id, {"action": "poll", "action_id": "wrong"}).ok, "Unrelated action identity cannot retrieve a result")
    supervisor.grace_ms = 100
    supervisor.request_stop(id)
    var stopped = await wait_for(supervisor, id, func(s): return s.state == "exited")
    check(stopped.stop_method == "forced", "Independent Stop recovers a hung action")
    check(not supervisor.request_action(id, {"action": "poll", "action_id": action.get("action_id")}).ok, "Polling interrupted action reports child exit")
    # Simulate losing the owner while the child's main thread is hung.
    supervisor.parent_grace_ms = 600
    workspace = fixture("ProcessOwnerLost", "extends Node\nfunc _ready():\n\twhile true:\n\t\tpass\n")
    started = supervisor.start(workspace)
    supervisor.heartbeat_enabled = false
    stopped = await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    check(stopped.get("stop_reason", "").contains("parent_lost"), "Watchdog terminates orphan even with hung game main thread")
    supervisor.heartbeat_enabled = true
    supervisor.parent_grace_ms = 15000
    supervisor.run_budget_bytes = 128 * 1024
    workspace = fixture("ProcessStorageFlood", "extends Node\nfunc _ready():\n\tvar f = FileAccess.open('user://large.dat', FileAccess.WRITE)\n\tf.store_buffer(PackedByteArray(range(300000)))\n\twhile true:\n\t\tpass\n")
    started = supervisor.start(workspace)
    stopped = await wait_for(supervisor, started.run_id, func(s): return s.state == "exited")
    check(stopped.get("stop_reason", "").contains("test_storage_budget"), "Watchdog stops user-data flood despite hung main thread")
    var evidence = load("res://src/core/test_evidence.gd")
    var test_root: String = stopped.path.get_base_dir()
    var retained = evidence.enforce(test_root, [], 1)
    check(retained.expired.size() > 0 and not DirAccess.dir_exists_absolute(stopped.path), "Completed run storage expires under per-game budget")
    check(stopped.get("session_path", "") != "" and not DirAccess.dir_exists_absolute(stopped.session_path), "Retention removes diagnostics even when startup hung before acceptance")
    check(str(supervisor.read_log(started.run_id, {})).contains("retention_expired"), "Expired evidence is reported explicitly")
    # Recovery records uncertainty instead of trusting a persisted process ID.
    var recovery_root = ProjectSettings.globalize_path("user://recovery-tests")
    var recovery_path = recovery_root.path_join("abandoned")
    JsonStore.write_dict(recovery_path.path_join("config.json"), {"run_id": "abandoned", "mode": "headless", "parent_token": "old"})
    JsonStore.write_dict(recovery_path.path_join("outcome.json"), {"run_id": "abandoned", "state": "running", "pid": OS.get_process_id()})
    JsonStore.write_dict(recovery_path.path_join("watchdog.json"), {"reason": "parent_lost", "method": "requested"})
    evidence.recover(recovery_root)
    var recovered = JsonStore.read_dict(recovery_path.path_join("outcome.json"), {})
    check(recovered.state == "interrupted", "Recovery does not claim an unconfirmed shutdown succeeded or kill a saved PID")
    JsonStore.write_dict(recovery_path.path_join("status.json"), {"state": "exited", "graceful_exit": true})
    evidence.recover(recovery_root)
    check(JsonStore.read_dict(recovery_path.path_join("outcome.json"), {}).state == "exited", "Recovery reconciles confirmed child termination")
    supervisor.runs.clear()
    supervisor.runs["active"] = {"state": "running"}
    for i in range(20):
        supervisor.runs[str(i)] = {"state": "exited"}
    supervisor._prune_runs()
    check(supervisor.runs.has("active") and supervisor.runs.size() == supervisor.MAX_RUNS, "Bounded history never evicts the live supervised process")
    supervisor.runs.clear()
    supervisor.queue_free()
    await process_frame

func test_bridge_and_prompt() -> void:
    var workspace = fixture("ProcessBridge", "extends Node\nconst Helper = preload('helper.gd')\nvar marker = Helper.VALUE\n")
    var helper = FileAccess.open(workspace.path_join("helper.gd"), FileAccess.WRITE)
    helper.store_string("extends RefCounted\nconst VALUE = 41\n")
    helper.close()
    var runner = preload("res://src/core/game_runner.gd").new()
    root.add_child(runner)
    runner.load_game(workspace)
    var game: Node = runner.active_game
    helper = FileAccess.open(workspace.path_join("helper.gd"), FileAccess.WRITE)
    helper.store_string("extends RefCounted\nconst VALUE = 99\n")
    helper.close()
    var attempt: int = runner.runtime_log.attempt_id
    var tools = GameTools.new(workspace, runner)
    var controller = preload("res://src/agent/pi_agent_controller.gd").new()
    root.add_child(controller)
    controller.configure("ProcessBridge", tools)
    controller.bridge_dir = ProjectSettings.globalize_path("user://process-bridge")
    var bridge: String = controller.bridge_dir
    JsonStore.write_dict(bridge.path_join("request-start.json"), {"id": "start", "command": "start_test_game", "args": {"mode": "headless"}})
    controller._service_host_bridge()
    var started = JsonStore.read_dict(bridge.path_join("response-start.json"), {})
    check(started.get("ok", false), "Production bridge starts a test without reload approval")
    if not started.get("ok", false):
        controller.queue_free()
        runner.queue_free()
        return
    var id: String = started.run_id
    await wait_for(tools.tests(), id, func(s): return s.state == "running")
    tools.tests().request_action(id, {"action": "inspect", "properties": ["marker"]})
    var inspected = await wait_for(tools.tests(), id, func(s): return s.has("action_result"))
    check(inspected.get("action_result", {}).get("properties", {}).get("marker") == "99" and game.get("marker") == 41, "Fresh child sees edited dependency while accepted game keeps old dependency")
    check(runner.active_game == game and runner.runtime_log.attempt_id == attempt, "Standalone testing leaves accepted game and live attempt untouched")
    check(controller.pending_reload.is_empty(), "Test launch does not request live reload permission")
    JsonStore.write_dict(bridge.path_join("request-stop.json"), {"id": "stop", "command": "stop_test_game", "args": {"run_id": id}})
    controller._service_host_bridge()
    check(not FileAccess.file_exists(bridge.path_join("response-stop.json")), "Stop response waits for actual child exit")
    JsonStore.write_dict(bridge.path_join("request-read.json"), {"id": "read", "command": "read_runtime_log", "args": {}})
    controller._service_host_bridge()
    check(FileAccess.file_exists(bridge.path_join("response-read.json")), "Live diagnostics bridge remains responsive during shutdown")
    await wait_for(tools.tests(), id, func(s): return s.state == "exited")
    controller._service_host_bridge()
    var stopped = JsonStore.read_dict(bridge.path_join("response-stop.json"), {})
    check(stopped.get("state") == "exited" and stopped.get("stop_method") == "graceful", "Production bridge delivers confirmed graceful stop")
    var settings = MetadataStore.new().global_settings()
    var config = preload("res://src/pi/pi_runtime_config.gd")
    var prepared = config.prepare("ProcessBridge", workspace, settings, {"openrouter": "test-key"}, {})
    check(prepared.ok, "Pi configuration prepares for prompt stability test")
    var prompt = FileAccess.get_file_as_string("user://host/games/ProcessBridge/pi/agent/APPEND_SYSTEM.md")
    settings.allow_rendered_tests = not bool(settings.get("allow_rendered_tests", false))
    config.prepare("ProcessBridge", workspace, settings, {"openrouter": "test-key"}, {})
    check(prompt != "" and prompt == FileAccess.get_file_as_string("user://host/games/ProcessBridge/pi/agent/APPEND_SYSTEM.md"), "Changing rendered permission leaves system instructions byte-identical")
    controller.queue_free()
    runner.queue_free()
    await process_frame
