extends SceneTree

class CorrectedAgent extends Node:
    var result_corrected := true
    var result_text := "Corrected answer"
    var recovery_error := ""

var failures := 0
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value: failures += 1

func run() -> void:
    var store = WorkspaceStore.new()
    store.ensure()
    var name = "Visible chat fixture"
    var created = store.create_game(name)
    check(created.ok, "creates isolated chat workspace")
    var transcript = TranscriptStore.new()
    for i in range(205): transcript.append(name, "assistant", "Legacy answer %d" % i)
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.current_game = name
    app._load_transcript()
    var old_text: String = app.transcript_view.get_parsed_text()
    check("Legacy answer 0\n" in old_text and "Legacy answer 204" in old_text, "migrates all existing saved dialogue, including more than 200 messages")
    app._append_chat("user", "Build [b]this[/b]")
    app._append_stream_delta("thinking", "Consider the palette.")
    app._end_stream_block("thinking")
    app._append_stream_delta("assistant", "First ")
    app._append_stream_delta("assistant", "commentary.")
    app._append_chat("tool", "generate_image status")
    app._append_stream_delta("assistant", "Second commentary.")
    app._append_chat("system", "Image ready.")
    app._append_stream_delta("assistant", "Final reply.")
    app._end_stream_block("assistant")
    app._append_stream_delta("system", "Native host notice.")
    app._end_stream_block("system")
    await process_frame
    var live: String = app.transcript_view.get_parsed_text()
    check("First commentary.\n\nTOOL\ngenerate_image status\n\nAGENT\nSecond commentary.\n\nHOST\nImage ready.\n\nAGENT\nFinal reply." in live, "interleaved tool/host messages close streams and next text gets a fresh role label")
    check("HOST\nNative host notice." in live, "system stream gets host flair")
    check("Build [b]this[/b]" in live, "literal BBCode remains literal")
    check(app.transcript_view.selection_enabled and app.transcript_view.context_menu_enabled, "chat supports text selection and copy menu")
    app.transcript_view.select_all()
    check(app.transcript_view.get_selected_text() == live, "selection exposes full visible text for copying")
    app.transcript_view.deselect()
    var filename: String = app.chat_history.path(name)
    var before: String = FileAccess.get_file_as_string(filename)
    app._load_transcript()
    check(app.transcript_view.get_parsed_text() == live and FileAccess.get_file_as_string(filename) == before, "replay is identical and never duplicates stored events")
    app.queue_free()
    await process_frame
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.current_game = name
    app._load_transcript()
    check(app.transcript_view.get_parsed_text() == live, "fresh app instance restores exactly the same live conversation from disk")
    check(transcript.read_all(name, 0).size() == 205, "visible thinking/tools/host notices never enter native conversation history")
    app._append_stream_delta("assistant", "Interrupted partial")
    live = app.transcript_view.get_parsed_text()
    app._load_transcript()
    check(app.transcript_view.get_parsed_text() == live, "unfinished stream survives reopening without invented endings")
    app._append_chat("system", "Stopped.")
    check("Interrupted partial\n\nHOST\nStopped." in app.transcript_view.get_parsed_text(), "host message after restored partial starts on its own line")
    app._reconcile_chat_history()
    check(not "Interrupted partial" in app.transcript_view.get_parsed_text() and "First commentary." in app.transcript_view.get_parsed_text() and "Stopped." in app.transcript_view.get_parsed_text(), "retry discards only abandoned stream, keeping earlier commentary and notices")
    app._append_stream_delta("assistant", "wrong result")
    app._end_stream_block("assistant")
    var corrected = CorrectedAgent.new()
    app.agent = corrected
    app._reconcile_chat_history()
    app.agent = null
    corrected.free()
    check("Corrected answer" in app.transcript_view.get_parsed_text() and not "wrong result" in app.transcript_view.get_parsed_text() and "First commentary." in app.transcript_view.get_parsed_text(), "native correction replaces only final stream and preserves intermediate history")
    var file = FileAccess.open(filename, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_string('{"type":"delta"')
    file.close()
    app._append_chat("system", "After interrupted write")
    app._load_transcript()
    check("After interrupted write" in app.transcript_view.get_parsed_text(), "incomplete final record cannot swallow next saved message")
    app.queue_free()
    await process_frame
    store.delete_game(name)
    print("CHAT HISTORY: %d failures" % failures)
    quit(1 if failures else 0)
