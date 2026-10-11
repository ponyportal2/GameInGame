extends SceneTree
var failures := 0
var app

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    print("PASS: " + message if value else "FAIL: " + message)
    if not value:
        failures += 1

func wait_idle() -> void:
    while app.agent.busy:
        await process_frame

func wait_reload() -> void:
    while app.agent.busy and app.agent.pending_reload.is_empty():
        await process_frame

func run() -> void:
    OS.set_environment("GAMESMITH_COMMAND_CODE_BIN", ProjectSettings.globalize_path("res://tools/testing/fake-command-code.mjs"))
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Command lifecycle"
    app.harness_option.select(1)
    app._create_game()
    app.agent.send_player_request("reload")
    await wait_reload()
    check(app.agent.busy and not app.agent.pending_reload.is_empty(), "command-code reload waits for approval")
    check(not app.runner.has_active_game(), "pending reload does not execute game code")
    app.agent.approve_reload()
    await wait_idle()
    check(app.agent.last_error == "" and app.runner.has_active_game(), "approved reload finishes the command-code request")
    app.agent.send_player_request("test")
    await wait_idle()
    check(app.agent.last_error == "", "command-code bridge starts and gracefully stops a test")
    app.agent.send_player_request("reload")
    await wait_reload()
    var old_pid = app.agent.rpc.pid
    app.agent.cancel()
    await process_frame
    check(not app.agent.busy and app.agent.pending_reload.is_empty(), "Stop cancels command-code and pending reload")
    check(not OS.is_process_running(old_pid), "Stop terminates the adapter process")
    app.agent.send_player_request("follow up")
    await wait_idle()
    check(app.agent.last_error == "", "a new request works after cancellation")
    app.queue_free()
    await process_frame
    OS.unset_environment("GAMESMITH_COMMAND_CODE_BIN")
    quit(1 if failures else 0)
