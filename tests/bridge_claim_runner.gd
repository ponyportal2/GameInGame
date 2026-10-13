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

func run() -> void:
    if OS.get_name() != "Windows":
        print("SKIP: bridge claim lock regression is Windows-specific")
        quit(0)
        return

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

    var marker = bridge.path_join("lock-ready.txt")
    OS.set_environment("GAMESMITH_LOCK_PATH", request_path)
    OS.set_environment("GAMESMITH_LOCK_MARKER", marker)
    var script = "$ErrorActionPreference='Stop'; $p=$env:GAMESMITH_LOCK_PATH; $m=$env:GAMESMITH_LOCK_MARKER; "
    script += "$f=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); "
    script += "[IO.File]::WriteAllText($m,'locked'); Start-Sleep -Milliseconds 1500; $f.Dispose()"
    var locked = OS.execute_with_pipe("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", script]), false)
    var lock_pid = int(locked.get("pid", -1))
    check(lock_pid > 0 and await wait_for_file(marker), "fixture holds request open without delete sharing")

    # The request is readable but cannot be deleted/renamed while the helper owns
    # it. A bridge consumer must not act on a request it failed to claim, because
    # the superclass would otherwise see and process the same request again.
    agent._service_host_bridge()
    check(agent.pending_reload.is_empty(), "locked authorization is not processed before exclusive claim")
    check(not FileAccess.file_exists(response_path), "locked authorization cannot receive a duplicate superclass response")

    check(await wait_for_exit(lock_pid), "fixture releases the request lock")
    OS.unset_environment("GAMESMITH_LOCK_PATH")
    OS.unset_environment("GAMESMITH_LOCK_MARKER")

    # Keep the second half useful even on the RED implementation so the failure
    # pinpoints duplicate processing rather than cascading into unrelated checks.
    agent._clear_pending_reload()
    if FileAccess.file_exists(response_path):
        DirAccess.remove_absolute(response_path)

    agent._service_host_bridge()
    check(not agent.pending_reload.is_empty(), "authorization is processed once after the request becomes claimable")
    check(not FileAccess.file_exists(response_path), "manual authorization still waits for player approval")
    agent.approve_reload()
    var response = JsonStore.read_dict(response_path, {})
    check(response.get("ok", false), "approved authorization receives one successful response")
    check(not FileAccess.file_exists(request_path), "claimed request is removed from the live request namespace")

    agent.busy = false
    agent.queue_free()
    await process_frame
    print("BRIDGE CLAIM REGRESSION: %d failure(s)" % failures)
    quit(1 if failures else 0)
