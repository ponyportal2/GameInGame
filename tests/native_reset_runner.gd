extends SceneTree

const CommandCode = preload("res://src/agent/command_code_agent_controller.gd")
const Inventory = preload("res://src/agent/harness_inventory.gd")

class RetiringSession extends RefCounted:
    var running := true
    var retired := false
    func retire() -> void:
        retired = true
        running = false

var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
    print(("PASS: " if value else "FAIL: ") + label)
    if not value: failures += 1

func wait_for_file(path: String) -> bool:
    var deadline = Time.get_ticks_msec() + 4000
    while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline:
        await process_frame
    return FileAccess.file_exists(path)

func hold_reference(path: String, marker: String) -> int:
    OS.set_environment("GAMESMITH_RESET_LOCK_PATH", ProjectSettings.globalize_path(path))
    OS.set_environment("GAMESMITH_RESET_LOCK_MARKER", ProjectSettings.globalize_path(marker))
    var script = "$ErrorActionPreference='Stop'; $f=[IO.File]::Open($env:GAMESMITH_RESET_LOCK_PATH,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); "
    script += "[IO.File]::WriteAllText($env:GAMESMITH_RESET_LOCK_MARKER,'locked'); Start-Sleep -Milliseconds 1500; $f.Dispose()"
    var child = OS.execute_with_pipe("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", script]), false)
    OS.unset_environment("GAMESMITH_RESET_LOCK_PATH")
    OS.unset_environment("GAMESMITH_RESET_LOCK_MARKER")
    return int(child.get("pid", -1))

func run() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Native reset isolation"
    for i in app.harness_option.item_count:
        if app.harness_option.get_item_metadata(i) == "opencode": app.harness_option.select(i)
    app._create_game()
    var directory = app.metadata.game_meta_dir(app.current_game)
    var command_path = directory.path_join("command-code/session.json")
    var open_path = directory.path_join("opencode/session.json")
    check(JsonStore.write_dict(command_path, {"session": "command-sentinel"}), "writes Command-code sentinel")
    check(JsonStore.write_dict(open_path, {"session": "opencode-sentinel"}), "writes OpenCode sentinel")
    var command_bytes = FileAccess.get_file_as_bytes(command_path)
    var open_bytes = FileAccess.get_file_as_bytes(open_path)

    var command = CommandCode.new()
    root.add_child(command)
    command.configure(app.current_game, app.tools)
    # Both controllers belong to this editor; denied ownership is tested separately.
    command.editor_guard = app.game_edit_guard
    var reset = command.start_new_session()
    check(reset.get("ok", false) and not FileAccess.file_exists(command_path), "Command-code resets its own active reference")
    check(FileAccess.get_file_as_bytes(str(reset.get("archive", ""))) == command_bytes, "Command-code archives the exact reference")
    check(FileAccess.get_file_as_bytes(open_path) == open_bytes, "Command-code reset preserves OpenCode reference")
    JsonStore.write_dict(command_path, {"session": "command-sentinel"})

    app._open_settings()
    check(Inventory.supports_reset("opencode") and app.codex_new_session_button.visible and "OpenCode" in app.codex_new_session_button.text, "OpenCode capability and UI expose its own reset")
    app._request_new_codex_session()
    check(app.codex_session_dialog.visible, "UI asks for OpenCode reset confirmation")
    app._cancel_new_codex_session()
    check(FileAccess.get_file_as_bytes(open_path) == open_bytes, "cancelling confirmation preserves OpenCode reference")
    app.agent.editor_guard = null
    var native = RetiringSession.new()
    app.agent.rpc = native
    app.agent.bridge_dir = "unchanged-bridge"
    app.agent.backend_pid = 12345
    app.agent.last_context_tokens = 456
    var generation: int = app.agent.operation_id
    var archives = DirAccess.get_files_at(ProjectSettings.globalize_path(command_path.get_base_dir()))
    app.agent.busy = true
    var rejected = app.agent.start_new_session()
    check(not rejected.get("ok", true) and "Stop OpenCode" in str(rejected.get("error", "")), "busy OpenCode reset is rejected")
    check(app.agent.busy and app.agent.editor_guard == null, "busy reset does not attempt ownership acquisition")
    app.agent.busy = false
    rejected = app.agent.start_new_session()
    check(not rejected.get("ok", true) and "another GameSmith" in str(rejected.get("error", "")), "non-owner OpenCode reset is rejected")
    check(app.agent.rpc == native and not native.retired and app.agent.bridge_dir == "unchanged-bridge" and app.agent.backend_pid == 12345 and app.agent.last_context_tokens == 456 and app.agent.operation_id == generation and not app.agent.editor_guard.owned, "rejected resets preserve native runtime without acquiring ownership")
    check(FileAccess.get_file_as_bytes(command_path) == command_bytes and FileAccess.get_file_as_bytes(open_path) == open_bytes, "rejected resets preserve both references")
    check(DirAccess.get_files_at(ProjectSettings.globalize_path(command_path.get_base_dir())) == archives, "rejected resets create no Command-code archives")
    app.agent.editor_guard = app.game_edit_guard
    if OS.get_name() == "Windows":
        var marker = directory.path_join("reset-lock-ready.txt")
        var pid = hold_reference(open_path, marker)
        check(pid > 0 and await wait_for_file(marker), "fixture locks OpenCode reference against rename")
        rejected = app.agent.start_new_session()
        check(not rejected.get("ok", true) and "No session was reset" in str(rejected.get("error", "")), "failed archive rejects OpenCode reset")
        check(app.agent.rpc == native and not native.retired and app.agent.bridge_dir == "unchanged-bridge" and app.agent.backend_pid == 12345 and app.agent.last_context_tokens == 456, "archive failure preserves the native runtime")
        check(FileAccess.get_file_as_bytes(open_path) == open_bytes and FileAccess.get_file_as_bytes(command_path) == command_bytes, "archive failure preserves exact provider references")
        var deadline = Time.get_ticks_msec() + 5000
        while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
            await process_frame
        check(pid > 0 and not OS.is_process_running(pid), "lock fixture exits before reset retry")
        if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
    var owned_reset = app.agent.start_new_session()
    check(owned_reset.get("ok", false) and not FileAccess.file_exists(open_path), "owned OpenCode reset removes only its active reference")
    check(FileAccess.get_file_as_bytes(str(owned_reset.get("archive", ""))) == open_bytes, "OpenCode archives the exact prior reference")
    check(app.agent.rpc == null and native.retired and app.agent.bridge_dir == "" and app.agent.backend_pid == -1 and app.agent.last_context_tokens == 0, "successful OpenCode reset retires runtime and clears stale status")
    check(FileAccess.get_file_as_bytes(command_path) == command_bytes, "OpenCode reset preserves Command-code reference")
    var empty_reset = app.agent.start_new_session()
    check(empty_reset.get("ok", false) and empty_reset.get("archive", "") == "", "OpenCode reset without a reference succeeds without an archive")
    JsonStore.write_dict(open_path, {"session": "opencode-sentinel"})

    command.busy = true
    check(not command.start_new_session().get("ok", true), "busy Command-code reset is rejected")
    check(FileAccess.get_file_as_bytes(command_path) == command_bytes and FileAccess.get_file_as_bytes(open_path) == open_bytes, "busy reset preserves both references")
    command.busy = false
    command.editor_guard = null
    check(not command.start_new_session().get("ok", true) and "another GameSmith" in command.last_error, "non-owner Command-code reset is rejected")
    check(FileAccess.get_file_as_bytes(command_path) == command_bytes and FileAccess.get_file_as_bytes(open_path) == open_bytes, "ownership-denied reset preserves both references")
    command.free()
    app.queue_free()
    await process_frame
    quit(1 if failures else 0)
