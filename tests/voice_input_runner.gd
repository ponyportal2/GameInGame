extends SceneTree

class CaptureFixture extends "res://src/core/voice_input.gd":
    var starts := 0
    var stops := 0
    func installed() -> bool: return true
    func _capture_start() -> bool:
        starts += 1
        return true
    func _capture_stop() -> AudioStreamWAV:
        stops += 1
        var audio = AudioStreamWAV.new()
        audio.format = AudioStreamWAV.FORMAT_16_BITS
        audio.mix_rate = 16000
        var data := PackedByteArray()
        data.resize(32000)
        audio.data = data
        return audio
    func _ensure_worker() -> bool:
        directory = ProjectSettings.globalize_path("user://voice-fixture")
        DirAccess.make_dir_recursive_absolute(directory)
        return true

class RecognitionFixture extends "res://src/core/voice_input.gd":
    var audio: AudioStreamWAV
    func _capture_start() -> bool: return true
    func _capture_stop() -> AudioStreamWAV: return audio

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
    for i in 5: await process_frame

func shortcut(action: String) -> void:
    # Screenshot capture resumes after drawing, when the host already polled
    # input. Inject on the next process frame so it observes the press once.
    await process_frame
    Input.action_press(action)
    await settle()
    Input.action_release(action)
    await settle()

func capture_picture(name: String) -> void:
    if DisplayServer.get_name() == "headless": return
    for arg in OS.get_cmdline_user_args():
        if not arg.begins_with("--captures="): continue
        var path = arg.trim_prefix("--captures=")
        DirAccess.make_dir_recursive_absolute(path)
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png(path.path_join(name + ".png"))

func picture_voice(app, agent, image: Image) -> void:
    check(app.annotation_editor.get("comment") is LineEdit, "picture editor has an editable comment")
    if not (app.annotation_editor.get("comment") is LineEdit): return
    app.voice.queue_free()
    var voice := CaptureFixture.new()
    app.voice = voice
    app.add_child(voice)
    # Recognition replies are injected below; this fixture has no worker to poll.
    voice.set_process(false)
    voice.configure({"voice_enabled":true})
    voice.bind_game(app.current_game)
    voice.changed.connect(app._voice_changed)
    voice.transcribed.connect(app._voice_transcribed)
    voice.set_draft("Separate gameplay voice draft")
    app._clear_picture_draft()
    app.chat_input.text = "Typed message"
    app._attach_picture(image, image, [])
    app.draft_pictures[0].caption = "First picture"
    app.annotation_editor.open(image)
    app.annotation_editor.comment.text = "Existing comment"
    voice.configure({"voice_enabled":false})
    var previous_status = voice.status
    var previous_message = agent.received
    await shortcut("record_voice")
    await shortcut("send_voice")
    check(voice.state == "idle" and voice.status == previous_status and voice.starts == 0, "disabled F8 does not start recording or report an error")
    check(app.annotation_editor.visible and app.annotation_editor.comment.text == "Existing comment" and app.draft_pictures.size() == 1 and app.chat_input.text == "Typed message" and agent.received == previous_message, "disabled F9 leaves the picture, comment and complete message untouched")
    voice.configure({"voice_enabled":true})
    await shortcut("record_voice")
    check(voice.state == "recording", "F8 starts recording while the picture editor is modal")
    await shortcut("record_voice")
    check(voice.state == "transcribing", "F8 stops picture recording for recognition")
    voice._consume_result({"id":voice.request_id, "ok":true, "text":"Make this red"})
    check(app.annotation_editor.comment.text == "Existing comment Make this red" and voice.draft == "Separate gameplay voice draft", "dictation appends to the current picture comment only")
    check(app.annotation_editor.visible and paused, "dictation without auto-send keeps the picture editor paused and editable")
    await capture_picture("voice-picture-comment")
    agent.busy = true
    await shortcut("send_voice")
    check(app.annotation_editor.visible and app.annotation_editor.comment.text.contains("Make this red"), "busy F9 retains the open picture and comment")
    agent.busy = false
    agent.reject = true
    await shortcut("send_voice")
    check(not app.annotation_editor.visible and app.draft_pictures.size() == 2 and app.chat_input.text == "Typed message", "rejected F9 retains typed text and all attached pictures")
    check(app.draft_pictures[1].caption == "Existing comment Make this red" and agent.received.contains("First picture") and agent.received.contains("Make this red"), "F9 submits the complete message with both picture comments")
    agent.reject = false
    app._edit_picture(1)
    check(app.annotation_editor.comment.text == "Existing comment Make this red", "editing a queued picture restores its comment")
    voice.settings.voice_auto_send = true
    app._toggle_voice()
    app._toggle_voice()
    voice._consume_result({"id":voice.request_id, "ok":true, "text":"And brighter"})
    check(not app.annotation_editor.visible and app.draft_pictures.is_empty() and app.chat_input.text == "", "picture auto-send attaches and sends the current message through admission")
    check(agent.received.contains("Typed message") and agent.received.contains("Make this red And brighter") and voice.draft == "Separate gameplay voice draft", "auto-send includes text, queued pictures and appended dictation without consuming gameplay draft")
    app.annotation_editor.open(image)
    app._toggle_voice()
    app._toggle_voice()
    var stale_id = voice.request_id
    app._cancel_annotation()
    app.annotation_editor.open(image)
    voice._consume_result({"id":stale_id, "ok":true, "text":"Wrong picture"})
    check(app.annotation_editor.comment.text == "" and voice.state == "idle", "closing the editor cancels recognition before another picture can receive it")
    voice.settings.voice_auto_send = false
    app.annotation_editor.comment.text = "Manual comment"
    app._toggle_voice()
    app._attach_picture(image, image, [])
    check(voice.state == "idle" and app.draft_pictures[0].caption == "Manual comment", "manual attach preserves the comment and stops picture recording")
    app._edit_picture(0)
    voice.settings.voice_auto_send = true
    app._toggle_voice()
    app._toggle_voice()
    agent.busy = true
    voice._consume_result({"id":voice.request_id, "ok":true, "text":"Keep while busy"})
    agent.busy = false
    await settle()
    check(app.annotation_editor.visible and app.annotation_editor.comment.text == "Manual comment Keep while busy", "busy picture auto-send keeps its comment without sending later")
    var last_request = agent.received
    app._toggle_voice()
    app._toggle_voice()
    voice._consume_result({"id":voice.request_id, "ok":true, "text":""})
    check(app.annotation_editor.visible and agent.received == last_request, "silence in the picture editor never auto-sends")
    app._toggle_voice()
    app._toggle_voice()
    voice._consume_result({"id":voice.request_id, "ok":false, "error":"Recognition failed"})
    check(app.annotation_editor.comment.text == "Manual comment Keep while busy" and agent.received == last_request, "recognition failure preserves the comment without auto-send")
    app._toggle_voice()
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    app._input(escape)
    check(app.annotation_editor.visible and voice.state == "idle" and app.annotation_editor.comment.text.contains("Keep while busy"), "Escape cancels picture recording before closing the editor")
    app._cancel_annotation()
    app.settings_dialog.show()
    app._toggle_voice()
    check(voice.state == "idle", "other host dialogs still block voice shortcuts")
    app.settings_dialog.hide()

func run() -> void:
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await settle()
    check(is_instance_valid(app.get("voice")), "host owns a voice controller")
    if not is_instance_valid(app.get("voice")):
        app.queue_free()
        await settle()
        quit(1)
        return
    app.store.create_game("Voice UI")
    app._open_game("Voice UI")
    var script = GDScript.new()
    script.source_code = "extends Node\nvar ticks = 0\nfunc _process(_dt): ticks += 1\n"
    check(script.reload() == OK, "gameplay fixture compiles")
    app.runner.active_game = script.new()
    app.runner.add_child(app.runner.active_game)
    app._set_chat_visible(false)
    app.agent.queue_free()
    var agent := FixtureAgent.new()
    app.add_child(agent)
    agent.configure(app.current_game, app.tools)
    app.agent = agent
    agent.player_request_accepted.connect(app._accept_chat_send)
    agent.finished.connect(app._on_agent_finished)
    var voice = app.voice
    check(voice.settings.get("voice_model", "base") == "base" and not voice.enabled(), "existing settings default to disabled multilingual base")
    check(not app.voice_composer.visible, "disabled voice does not expand the chat composer")
    voice.set_draft("Existing disabled draft")
    await shortcut("send_voice")
    check(voice.draft == "Existing disabled draft" and agent.received == "", "disabled send shortcut preserves a gameplay voice draft")
    app.voice_send_button.pressed.emit()
    check(agent.received == "Existing disabled draft" and voice.draft == "", "explicit Send voice still submits an existing draft with shortcuts disabled")
    agent.received = ""
    voice.configure({"voice_enabled":true})
    voice.bind_game(app.current_game)
    for arg in OS.get_cmdline_user_args():
        if not arg.begins_with("--recognition-wav="): continue
        var recognition := RecognitionFixture.new()
        root.add_child(recognition)
        recognition.configure({"voice_enabled":true})
        recognition.bind_game("Real recognition")
        recognition.audio = AudioStreamWAV.load_from_file(arg.trim_prefix("--recognition-wav="))
        check(recognition.audio != null and recognition.installed(), "real local-recognition environment and WAV are available")
        recognition.toggle_recording()
        recognition.toggle_recording()
        var deadline = Time.get_ticks_msec() + 60000
        while recognition.state == "transcribing" and Time.get_ticks_msec() < deadline: await process_frame
        check(recognition.draft.to_lower().contains("enemies") and recognition.draft.to_lower().contains("red"), "Godot controller receives real Whisper text through production worker IPC")
        check(recognition.worker_pid > 0 and OS.is_process_running(recognition.worker_pid), "successful transcription keeps the worker warm")
        recognition.queue_free()
    if "--microphone" in OS.get_cmdline_user_args():
        var previous_device = AudioServer.input_device
        var previous_buses = AudioServer.bus_count
        var capturing = voice._capture_start()
        check(capturing, "actual microphone capture starts")
        if capturing:
            check(AudioServer.is_bus_mute(AudioServer.get_bus_index(voice.bus_name)), "actual microphone bus is muted to prevent feedback")
            await create_timer(1.0).timeout
            var recorded = voice._capture_stop()
            check(recorded != null and recorded.get_length() > 0.5, "actual microphone produces PCM without pausing gameplay")
            check(AudioServer.bus_count == previous_buses and AudioServer.input_device == previous_device, "stopping capture restores audio routing")
    app.chat_input.text = "Unsent typed draft"
    var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
    image.fill(Color.BLUE)
    app._attach_picture(image, image, [])
    app._set_chat_visible(false)
    var mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.get_name() == "headless" else Input.MOUSE_MODE_CAPTURED
    Input.mouse_mode = mode
    var focus = root.gui_get_focus_owner()
    var ticks = app.runner.active_game.ticks
    voice.set_draft("Make grenades red")
    await settle()
    await capture_picture("voice-gameplay")
    agent.busy = true
    app._send_voice()
    check(voice.draft == "Make grenades red" and agent.received == "", "busy agent preserves voice draft without queuing a send")
    agent.busy = false
    agent.reject = true
    app._send_voice()
    check(voice.draft == "Make grenades red", "admission rejection preserves voice draft")
    agent.reject = false
    app._send_voice()
    await settle()
    check(agent.received == "Make grenades red" and voice.draft == "", "accepted voice sends ordinary text and clears only its draft")
    check(app.chat_input.text == "Unsent typed draft" and app.draft_pictures.size() == 1, "voice send preserves typed text and queued pictures")
    check(not paused and not app.chat_overlay.visible and app.runner.active_game.ticks > ticks, "game keeps processing through submission and completion")
    check(Input.mouse_mode == mode and root.gui_get_focus_owner() == focus, "voice send preserves mouse capture and keyboard focus")
    voice.set_draft("Shortcut message")
    Input.action_press("send_voice")
    await settle()
    Input.action_release("send_voice")
    check(agent.received == "Shortcut message" and voice.draft == "", "send shortcut works during gameplay without opening chat")
    voice.settings.voice_auto_send = true
    voice.request_id = "auto"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    voice._consume_result({"id":"auto", "ok":true, "text":"Automatic message"})
    check(agent.received == "Automatic message" and voice.draft == "", "opt-in auto-send uses the same admission path")
    agent.busy = true
    voice.request_id = "auto-busy"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    voice._consume_result({"id":"auto-busy", "ok":true, "text":"Kept while busy"})
    agent.busy = false
    await settle()
    check(voice.draft == "Kept while busy" and agent.received == "Automatic message", "busy auto-send is preserved and never secretly sent later")
    voice.settings.voice_auto_send = false
    voice.set_draft("Edit me")
    app.voice_draft_edit.text = "Edited transcript"
    app.voice_draft_edit.text_changed.emit()
    check(voice.draft == "Edited transcript", "voice transcript is editable independently of chat")
    voice.request_id = "before-rename"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    app._open_rename(app.current_game)
    app.rename_edit.text = "Voice UI renamed"
    app._rename_game()
    check(app.current_game == "Voice UI renamed" and voice.game_name == app.current_game and voice.draft == "Edited transcript" and voice.state == "idle", "renaming the current game preserves its voice draft and cancels active transcription")
    voice._consume_result({"id":"before-rename", "ok":true, "text":"stale rename result"})
    check(voice.draft == "Edited transcript", "a cancelled transcription cannot append after rename")
    voice.request_id = "old-request"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    voice.bind_game("Another game")
    voice._consume_result({"id":"old-request", "ok":true, "text":"stale text"})
    check(voice.draft == "" and voice.state == "idle", "late result cannot enter another game's voice draft")
    voice.bind_game(app.current_game)
    voice.request_id = "silence"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    voice._consume_result({"id":"silence", "ok":true, "text":""})
    check(voice.draft == "" and voice.state == "idle", "empty recognition never sends a message")
    voice.set_draft("keep after failure")
    voice.request_id = "failure"
    voice.request_game = app.current_game
    voice.state = "transcribing"
    voice._consume_result({"id":"failure", "ok":false, "error":"No microphone"})
    check(voice.draft == "keep after failure" and voice.status.contains("No microphone"), "recognition error preserves existing draft and explains failure")
    voice.request_id = "cancelled"
    voice.state = "transcribing"
    voice.cancel()
    voice._consume_result({"id":"cancelled", "ok":true, "text":"must not send"})
    check(voice.draft == "keep after failure", "cancel discards pending recognition without erasing earlier draft")
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.pressed = true
    app._set_chat_visible(true)
    voice.state = "recording"
    app._input(escape)
    check(app.chat_overlay.visible and voice.state == "idle", "Escape cancels voice before closing chat")
    root.size = Vector2i(1024, 640)
    await settle()
    check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(app.send_button.get_global_rect()), "voice editor and queued picture leave Send visible at minimum window size")
    await capture_picture("voice-chat")
    app._open_settings()
    var voice_ui = preload("res://src/ui/voice_ui.gd")
    var microphone = app.voice_settings.microphone
    voice_ui.refresh_microphones(microphone, "USB microphone", PackedStringArray(["Default", "USB microphone"]))
    check(microphone.item_count == 2 and voice_ui.values(app).voice_microphone == "USB microphone", "refreshed microphone choices select a newly connected device")
    voice_ui.refresh_microphones(microphone, "USB microphone", PackedStringArray(["Default"]))
    check(voice_ui.values(app).voice_microphone == "USB microphone" and microphone.get_item_text(microphone.selected).contains("unavailable"), "an absent saved microphone remains selected without changing its stored value")
    voice_ui.refresh_microphones(microphone, "USB microphone", PackedStringArray(["Default", "USB microphone"]))
    check(microphone.item_count == 2 and microphone.get_item_text(microphone.selected) == "USB microphone", "a reconnected microphone replaces its unavailable entry")
    voice_ui.refresh_microphones(microphone, "USB microphone", PackedStringArray())
    check(microphone.item_count == 1 and voice_ui.values(app).voice_microphone == "USB microphone", "an empty device list still preserves the remembered microphone")
    app.metadata.save_global_settings({"voice_microphone":"Missing fixture microphone"})
    app._open_settings()
    check(voice_ui.values(app).voice_microphone == "Missing fixture microphone" and microphone.get_item_text(microphone.selected).contains("unavailable"), "reopening Settings preserves an unavailable saved device through the save-value path")
    app.metadata.save_global_settings({"voice_microphone":"Default"})
    microphone.add_item("stale device")
    app._open_settings()
    var device_names: Array = []
    for i in microphone.item_count: device_names.append(microphone.get_item_text(i))
    check(not device_names.has("stale device") and voice_ui.values(app).voice_microphone == "Default", "opening Settings refreshes actual devices and selects the saved microphone")
    var tabs = app.settings_dialog.find_child("SettingsTabs", true, false)
    tabs.current_tab = 3
    await settle()
    await capture_picture("voice-settings")
    check(app.voice_settings.model.get_item_metadata(app.voice_settings.model.selected) == "base", "Voice settings expose default model")
    app.voice_settings.model.select(0)
    app.voice_settings.enabled.button_pressed = true
    var saved = preload("res://src/ui/voice_ui.gd").values(app)
    check(saved.voice_model == "tiny" and saved.voice_enabled and not saved.has("voice_python") and not app.voice_settings.has("python"), "Voice settings use included Python without a system executable field")
    app.metadata.save_global_settings(saved)
    app.settings_dialog.hide()
    app._apply_voice_settings()
    check(voice.settings.voice_model == "tiny" and InputMap.action_get_events("send_voice")[0].physical_keycode == KEY_F9, "saved voice settings configure controller and shortcut")
    var capture := CaptureFixture.new()
    root.add_child(capture)
    capture.configure({"voice_enabled":true, "voice_model":"tiny"})
    capture.bind_game("Capture test")
    capture.toggle_recording()
    check(capture.state == "recording" and capture.starts == 1, "record toggle starts capture")
    capture.toggle_recording()
    var audio_path = capture.directory.path_join(capture.request_id + ".wav")
    check(capture.state == "transcribing" and FileAccess.file_exists(audio_path), "stop toggle saves temporary WAV and requests transcription")
    var request = JsonStore.read_dict(capture.directory.path_join("request-" + capture.request_id + ".json"))
    check(request.model == "tiny" and request.audio == audio_path, "recording request carries selected model and session-owned audio")
    capture.cancel()
    check(capture.state == "idle" and not FileAccess.file_exists(audio_path), "cancelling removes temporary recording and request")
    capture.set_draft("Keep on rename")
    capture.toggle_recording()
    var capture_stops = capture.stops
    capture.rebind_game("Capture test renamed")
    check(capture.state == "idle" and capture.stops == capture_stops + 1 and capture.draft == "Keep on rename", "rename cancels recording and releases capture while retaining the draft")
    capture.toggle_recording()
    capture._process(60.1)
    check(capture.state == "transcribing", "maximum recording duration stops automatically")
    capture.cancel()
    capture.toggle_recording()
    capture._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(capture.state == "idle" and capture.status.contains("lost focus"), "focus loss cancels recording instead of leaving the microphone running")
    capture.state = "installing"
    capture.status = "Installing local recognition"
    capture.bind_game("")
    capture.configure({"voice_enabled":false})
    check(capture.state == "installing" and capture.status == "Installing local recognition", "navigation and settings changes leave explicit installation running")
    capture.state = "idle"
    capture.queue_free()
    await picture_voice(app, agent, image)
    voice = app.voice
    app._show_library()
    check(voice.game_name == "" and voice.draft == "", "library navigation clears voice context")
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    app.queue_free()
    await settle()
    print("Voice input: %d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)
