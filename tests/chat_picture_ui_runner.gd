extends SceneTree

class FixtureAgent extends "res://src/agent/agent_controller_base.gd":
    var reject := false
    var received := ""
    func acquire_editor() -> bool: return true
    func _send_player_attempt(text: String) -> void:
        received = text
        busy = true
        if not reject:
            _record_player_request(text)
            request_admitted = true
        busy = false
        finished.emit(not reject)

var passed := 0
var failed := 0

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
    if value:
        passed += 1
        print("PASS: ", message)
    else:
        failed += 1
        push_error("FAIL: " + message)
func settle() -> void:
    for i in 4: await process_frame

func run() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await settle()
    app.store.create_game("Pictures UI")
    app._open_game("Pictures UI")
    var previous = app.agent
    previous.queue_free()
    var agent := FixtureAgent.new()
    app.add_child(agent)
    agent.configure(app.current_game, app.tools)
    app.agent = agent
    agent.player_request_accepted.connect(app._accept_chat_send)
    agent.finished.connect(app._on_agent_finished)
    var image := Image.create(100, 60, false, Image.FORMAT_RGBA8)
    image.fill(Color.BLUE)
    app.chat_input.text = "Fix the marked area"
    app._attach_picture(image, image, [])
    app._attach_picture(image, image, [])
    check(app.draft_pictures.size() == 2 and app.chat_input.text == "Fix the marked area", "multiple captures preserve the existing text and pictures")
    app.draft_pictures[0].caption = "First problem"
    var removed: String = app.draft_pictures[1].id
    app._remove_picture(1)
    check(app.draft_pictures.size() == 1 and not app.picture_store.inspect_picture(removed).ok, "removing a draft removes only its PNG")
    app._edit_picture(0)
    check(app.annotation_editor.visible and app.annotation_editor.canvas.picture != null, "queued picture can be reopened for editing")
    app._cancel_annotation()
    check(app.draft_pictures.size() == 1 and app.chat_overlay.visible and paused, "cancel editing retains the draft and chat pause")
    var old_id: String = app.draft_pictures[0].id
    app._edit_picture(0)
    app._attach_picture(image, image, [])
    check(app.draft_pictures[0].id != old_id and app.draft_pictures[0].caption == "First problem" and not app.picture_store.inspect_picture(old_id).ok, "saving an edited picture replaces its PNG and retains its caption")
    agent.busy = true
    app._remove_picture(0)
    app._edit_picture(0)
    check(app.draft_pictures.size() == 1 and not app.annotation_editor.visible, "busy request prevents editing or deleting its draft")
    agent.busy = false
    agent.reject = true
    app._send_chat()
    check(app.chat_input.text == "Fix the marked area" and app.draft_pictures.size() == 1, "rejected send retains text and attachments")
    check(app.chat_history.read_all(app.current_game).filter(func(event): return event.role == "user").is_empty(), "rejected send is not recorded as delivered")
    agent.reject = false
    app._send_chat()
    check("inspect_attachment" in agent.received and "First problem" in agent.received, "agent receives actual attachment identities and captions")
    check(app.chat_input.text == "" and app.draft_pictures.is_empty(), "accepted send clears only the delivered draft")
    await settle()
    check(not "inspect_attachment" in app.transcript_view.get_parsed_text() and not ".png" in app.transcript_view.get_parsed_text(), "visible chat hides transport instructions and file names")
    var events: Array = app.chat_history.read_all(app.current_game)
    var user: Dictionary = events.filter(func(event): return event.role == "user").back()
    check(user.pictures.size() == 1 and user.content == "Fix the marked area", "delivered history contains clean text and image metadata")
    var id: String = user.pictures[0].id
    check(app.tools.execute("inspect_attachment", {"id": id}).ok, "production tool facade can read the delivered PNG")
    app._load_transcript()
    await settle()
    check("First problem" in app.transcript_view.get_parsed_text(), "reopened chat renders the saved caption")
    app.chat_input.text = ""
    app._attach_picture(image, image, [])
    app._send_chat()
    check(app.draft_pictures.is_empty() and "inspect_attachment" in agent.received, "picture-only messages can be sent")
    root.size = Vector2i(1024, 640)
    for i in 6: app._attach_picture(image, image, [])
    await settle()
    check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(app.send_button.get_global_rect()), "queued pictures leave Send visible at minimum window size")
    check(app.picture_strip.get_child_count() == 6, "all queued pictures remain available in the scroll strip")
    var missing_id: String = app.draft_pictures[0].id
    app.picture_store.remove_draft(missing_id)
    var previous_request: String = agent.received
    app._send_chat()
    check(agent.received == previous_request and app.draft_pictures.size() == 6, "missing PNG prevents sending without losing the draft")
    app._show_library()
    app.queue_free()
    await settle()
    print("Picture UI assertions: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
