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
    check(not Inventory.supports_reset("opencode") and not app.codex_new_session_button.visible, "OpenCode capability and UI withhold reset")
    app._request_new_codex_session()
    check(not app.codex_session_dialog.visible and app.codex_session_game == "", "UI refuses to open an OpenCode reset confirmation")
    # A direct unsupported call must not acquire ownership or retire any runtime.
    app.agent.editor_guard = null
    var native = RetiringSession.new()
    app.agent.rpc = native
    app.agent.bridge_dir = "unchanged-bridge"
    app.agent.backend_pid = 12345
    app.agent.last_context_tokens = 456
    var generation: int = app.agent.operation_id
    var archives = DirAccess.get_files_at(ProjectSettings.globalize_path(command_path.get_base_dir()))
    for active in [false, true]:
        app.agent.busy = active
        var rejected = app.agent.start_new_session()
        check(not rejected.get("ok", true) and "unsupported" in str(rejected.get("error", "")).to_lower(), "direct OpenCode reset is unsupported, busy=" + str(active))
        check(app.agent.busy == active and app.agent.rpc == native and not native.retired and app.agent.bridge_dir == "unchanged-bridge" and app.agent.backend_pid == 12345 and app.agent.last_context_tokens == 456 and app.agent.operation_id == generation and app.agent.editor_guard == null, "unsupported OpenCode reset preserves runtime and ownership state")
        check(FileAccess.get_file_as_bytes(command_path) == command_bytes and FileAccess.get_file_as_bytes(open_path) == open_bytes, "unsupported OpenCode reset preserves both references")
    check(DirAccess.get_files_at(ProjectSettings.globalize_path(command_path.get_base_dir())) == archives, "unsupported reset creates no archives")
    app.agent.busy = false
    app.agent.editor_guard = app.game_edit_guard
    var owned_reset = app.agent.start_new_session()
    check(not owned_reset.get("ok", true) and "unsupported" in str(owned_reset.get("error", "")).to_lower(), "OpenCode reset is unsupported even with valid ownership")
    check(app.agent.rpc == native and not native.retired and app.agent.bridge_dir == "unchanged-bridge" and app.agent.backend_pid == 12345 and app.agent.last_context_tokens == 456, "owned OpenCode reset preserves the runtime")
    check(FileAccess.get_file_as_bytes(command_path) == command_bytes and FileAccess.get_file_as_bytes(open_path) == open_bytes, "owned OpenCode reset preserves both provider references")
    app.agent.rpc = null
    app.agent.bridge_dir = ""

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
