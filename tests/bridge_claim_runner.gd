extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value:
        failures += 1

func _init() -> void:
    call_deferred("run")

func wait_for_file(path: String, timeout_ms: int = 4000) -> bool:
    var deadline = Time.get_ticks_msec() + timeout_ms
    while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
        await process_frame
    return FileAccess.file_exists(path)

func wait_for_exit(pid: int, timeout_ms: int = 5000) -> bool:
    var deadline = Time.get_ticks_msec() + timeout_ms
    while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
        await process_frame
    return pid <= 0 or not OS.is_process_running(pid)

func hold_without_delete(path: String, marker: String) -> int:
    OS.set_environment("GAMESMITH_LOCK_PATH", path)
    OS.set_environment("GAMESMITH_LOCK_MARKER", marker)
    var script = "$ErrorActionPreference='Stop'; $p=$env:GAMESMITH_LOCK_PATH; $m=$env:GAMESMITH_LOCK_MARKER; "
    script += "$f=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); "
    script += "[IO.File]::WriteAllText($m,'locked'); Start-Sleep -Milliseconds 1500; $f.Dispose()"
    var locked = OS.execute_with_pipe("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", script]), false)
    return int(locked.get("pid", -1))

func clear_lock_env() -> void:
    OS.unset_environment("GAMESMITH_LOCK_PATH")
    OS.unset_environment("GAMESMITH_LOCK_MARKER")

func run() -> void:
    if OS.get_name() != "Windows":
        print("SKIP: bridge claim lock regression is Windows-specific")
        quit(0)
        return

    await test_cline_special_requests()
    await test_base_request()
    print("BRIDGE CLAIM REGRESSION: %d failure(s)" % failures)
    quit(1 if failures else 0)

func test_cline_special_requests() -> void:
    var bridge = ProjectSettings.globalize_path("user://bridge-claim-regression")
    DirAccess.make_dir_recursive_absolute(bridge)
    for file in DirAccess.get_files_at(bridge):
        DirAccess.remove_absolute(bridge.path_join(file))

    var agent = preload("res://src/agent/cline_agent_controller.gd").new()
    root.add_child(agent)
    agent.set_process(false)
    agent.game_name = "Bridge Claim Regression"
    agent.bridge_dir = bridge
    agent.busy = true
    agent.operation_id = 1
    var settings = agent.metadata.global_settings()
    settings.auto_approve_reloads = false
    agent.metadata.save_global_settings(settings)

    var request = {"id": "locked-authorization", "command": "authorize_reload", "args": {"token": "grant-token"}}
    var request_path = bridge.path_join("request-locked-authorization.json")
    var response_path = bridge.path_join("response-locked-authorization.json")
    check(JsonStore.write_dict(request_path, request), "fixture writes reload authorization request")

    var marker = bridge.path_join("authorization-lock-ready.txt")
    var lock_pid = hold_without_delete(request_path, marker)
    check(lock_pid > 0 and await wait_for_file(marker), "fixture holds authorization open without delete sharing")

    # The request is readable but cannot be deleted/renamed while the helper owns
    # it. A bridge consumer must not act on a request it failed to claim, because
    # the superclass would otherwise see and process the same request again.
    agent._service_host_bridge()
    check(agent.pending_reload.is_empty(), "locked authorization is not processed before exclusive claim")
    check(not FileAccess.file_exists(response_path), "locked authorization cannot receive a duplicate superclass response")

    check(await wait_for_exit(lock_pid), "fixture releases the authorization lock")
    clear_lock_env()

    agent._service_host_bridge()
    check(not agent.pending_reload.is_empty(), "authorization is processed once after the request becomes claimable")
    check(not FileAccess.file_exists(response_path), "manual authorization still waits for player approval")
    agent.approve_reload()
    var response = JsonStore.read_dict(response_path, {})
    check(response.get("ok", false), "approved authorization receives one successful response")
    check(not FileAccess.file_exists(request_path), "claimed authorization leaves the live request namespace")

    # The second ACP stage has the same claim requirement. An invalid token keeps
    # the fixture independent of GameTools while still exercising reload_game's
    # special bridge branch and its response path.
    request = {"id": "locked-reload", "command": "reload_game", "args": {"approval_token": "wrong-token"}}
    request_path = bridge.path_join("request-locked-reload.json")
    response_path = bridge.path_join("response-locked-reload.json")
    check(JsonStore.write_dict(request_path, request), "fixture writes grant-backed reload request")
    marker = bridge.path_join("reload-lock-ready.txt")
    lock_pid = hold_without_delete(request_path, marker)
    check(lock_pid > 0 and await wait_for_file(marker), "fixture holds reload request open without delete sharing")
    agent._service_host_bridge()
    check(not FileAccess.file_exists(response_path), "locked reload request is not rejected before exclusive claim")
    check(FileAccess.file_exists(request_path), "unclaimable reload request remains available for retry")
    check(await wait_for_exit(lock_pid), "fixture releases the reload request lock")
    clear_lock_env()
    agent._service_host_bridge()
    response = JsonStore.read_dict(response_path, {})
    check(response.has("ok") and not response.get("ok", true), "claimed invalid reload receives its normal grant error")
    check(not FileAccess.file_exists(request_path), "claimed reload request leaves the live request namespace")

    agent.busy = false
    agent.queue_free()
    await process_frame

func test_base_request() -> void:
    var bridge = ProjectSettings.globalize_path("user://bridge-claim-base-regression")
    DirAccess.make_dir_recursive_absolute(bridge)
    for file in DirAccess.get_files_at(bridge):
        DirAccess.remove_absolute(bridge.path_join(file))

    var agent = preload("res://src/agent/pi_agent_controller.gd").new()
    root.add_child(agent)
    agent.set_process(false)
    agent.bridge_dir = bridge

    var request = {"id": "locked-base", "command": "compaction_status", "args": {}}
    var request_path = bridge.path_join("request-locked-base.json")
    var response_path = bridge.path_join("response-locked-base.json")
    check(JsonStore.write_dict(request_path, request), "fixture writes real base bridge request")
    var marker = bridge.path_join("lock-ready.txt")
    var lock_pid = hold_without_delete(request_path, marker)
    check(lock_pid > 0 and await wait_for_file(marker), "fixture locks base request without delete sharing")

    agent._service_host_bridge()
    check(not FileAccess.file_exists(response_path), "base bridge does not execute a request before claiming it")
    check(FileAccess.file_exists(request_path), "unclaimable base request remains available for retry")

    check(await wait_for_exit(lock_pid), "fixture releases base request lock")
    clear_lock_env()
    agent._service_host_bridge()
    var response = JsonStore.read_dict(response_path, {})
    check(response.get("ok", false), "base bridge executes normal command after exclusive claim")
    check(not FileAccess.file_exists(request_path), "base claimed request leaves the live namespace")

    agent.queue_free()
    await process_frame
