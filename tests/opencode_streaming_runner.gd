extends SceneTree

var app
var streamed_while_busy = false
var kinds: Array[String] = []

func _init() -> void:
    call_deferred("run")

func run() -> void:
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "OpenCode live streaming"
    app.harness_option.select(2)
    app._create_game()
    app.agent.llm_stream_delta.connect(func(kind: String, text: String):
        if app.agent.busy and not text.is_empty():
            streamed_while_busy = true
            if kind not in kinds:
                kinds.append(kind)
    )
    app.agent.send_player_request("Without tools, explain how you would test a rotating platform game in five sentences. Think through the tricky cases before answering. Do not edit or reload the game.")
    while app.agent.busy:
        await process_frame
    var passed = streamed_while_busy and app.agent.last_error == "" and "assistant" in kinds
    print(("PASS: " if passed else "FAIL: ") + "installed OpenCode streams into GameSmith while the request is busy: " + str(kinds))
    app.queue_free()
    await process_frame
    quit(0 if passed else 1)
