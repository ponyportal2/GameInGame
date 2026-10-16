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
    check_reconcile_modes(store)
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
    app._append_chat("user", "Correct this turn")
    app._append_stream_delta("thinking", "Keep the evidence")
    app._append_stream_delta("assistant", "Commentary A")
    app._append_chat("tool", "read_file evidence")
    app._append_chat("system", "Host evidence")
    app._append_stream_delta("assistant", "wrong result")
    app._end_stream_block("assistant")
    var corrected = CorrectedAgent.new()
    corrected.result_text = "Commentary A\n\nCorrected answer"
    app.agent = corrected
    app._reconcile_chat_history()
    app.agent = null
    corrected.free()
    live = app.transcript_view.get_parsed_text()
    check(live.count("Commentary A") == 1 and "Corrected answer" in live and not "wrong result" in live, "whole-turn correction includes earlier commentary exactly once")
    check("Keep the evidence" in live and "read_file evidence" in live and "Host evidence" in live and "First commentary." in live, "whole-turn correction preserves non-assistant evidence and previous requests")
    app.queue_free()
    await process_frame
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.current_game = name
    app._load_transcript()
    check(app.transcript_view.get_parsed_text() == live, "fresh-app replay retains corrected interleaved turn without duplication")
    app = await check_batching(app, name)
    var file = FileAccess.open(filename, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_string('{"type":"delta"')
    file.close()
    app._append_chat("system", "After interrupted write")
    app._load_transcript()
    check("After interrupted write" in app.transcript_view.get_parsed_text(), "incomplete final record cannot swallow next saved message")
    app._record_chat_event({"type": "delta", "role": "assistant", "content": "z ".repeat(8192)})
    check("z ".repeat(8192) in FileAccess.get_file_as_string(filename), "size threshold flushes large pending fragments")
    app.queue_free()
    await process_frame
    store.delete_game(name)
    print("CHAT HISTORY: %d failures" % failures)
    quit(1 if failures else 0)

func check_batching(app, name: String):
    var filename: String = app.chat_history.path(name)
    app._append_chat("user", "Batch streaming output")
    var before = FileAccess.get_file_as_string(filename)
    for i in 1000: app._append_stream_delta("assistant", "x")
    check(FileAccess.get_file_as_string(filename) == before, "1000 small deltas render without per-delta disk writes")
    app._append_chat("tool", "Boundary")
    var events = app.chat_history.read_all(name)
    check(events[-3].content == "x".repeat(1000) and events[-2].type == "end" and events[-1].content == "Boundary", "buffer flush precedes end and tool events with one combined delta")
    app._append_stream_delta("thinking", "Periodic fragment")
    # A SceneTree timer can include time spent laying out earlier messages in
    # this frame; use the same monotonic clock as the actual flush deadline.
    var deadline = Time.get_ticks_msec() + 700
    while Time.get_ticks_msec() < deadline:
        await process_frame
    await process_frame
    check("Periodic fragment" in FileAccess.get_file_as_string(filename), "active stream is periodically persisted without a boundary")
    app._append_stream_delta("assistant", "Replay fragment")
    app._load_transcript()
    check("Replay fragment" in app.transcript_view.get_parsed_text(), "replay flushes pending deltas before reading")
    app._append_stream_delta("assistant", "Shutdown fragment")
    app.queue_free()
    await process_frame
    check("Shutdown fragment" in FileAccess.get_file_as_string(filename), "app shutdown flushes pending stream")
    # Caller needs a live app for the interrupted-write regression.
    app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.current_game = name
    app._load_transcript()
    app._append_stream_delta("assistant", "Navigation fragment")
    app._show_library()
    check("Navigation fragment" in FileAccess.get_file_as_string(filename), "leaving game flushes to its original history")
    app.current_game = name
    app._load_transcript()
    app._append_stream_delta("assistant", "Switch fragment")
    var store = WorkspaceStore.new()
    var other = store.create_game("Other chat fixture")
    app._open_game(other.name)
    check("Switch fragment" in FileAccess.get_file_as_string(filename) and not "Switch fragment" in FileAccess.get_file_as_string(app.chat_history.path(other.name)), "switching games flushes pending text to the original game only")
    app._show_library()
    store.delete_game(other.name)
    app.current_game = name
    app._load_transcript()
    return app

func check_reconcile_modes(store) -> void:
    var made = store.create_game("Reconcile modes fixture")
    var history = preload("res://src/core/chat_history.gd").new()
    history.seed(made.name, [{"role": "user", "content": "Request"}])
    history.append(made.name, {"type": "delta", "role": "assistant", "content": "Earlier"})
    history.append(made.name, {"type": "end", "role": "assistant"})
    history.append(made.name, {"type": "message", "role": "tool", "content": "Evidence"})
    history.append(made.name, {"type": "delta", "role": "assistant", "content": "Abandoned"})
    # Old persisted records have no mode and must preserve their old meaning.
    history.append(made.name, {"type": "reconcile", "content": ""})
    var events = history.read_all(made.name)
    check(events.size() == 4 and events[1].content == "Earlier" and events[-1].content == "Evidence", "legacy reconciliation defaults to latest stream and preserves earlier commentary")
    history.append(made.name, {"type": "message", "role": "assistant", "content": "Standalone prose"})
    history.append(made.name, {"type": "reconcile", "mode": "whole_turn", "content": ""})
    events = history.read_all(made.name)
    check(events.size() == 2 and events[-1].role == "tool", "explicit empty whole-turn correction removes assistant prose and ends but retains evidence")
    history.append(made.name, {"type": "reconcile", "mode": "whole_turn", "content": "Canonical"})
    events = history.read_all(made.name)
    check(events.size() == 3 and events[1].content == "Canonical" and events[2].role == "tool", "whole-turn canonical output without prior prose is inserted after user")
    history.append(made.name, {"type": "reconcile", "mode": "whole_turn", "content": "Canonical"})
    events = history.read_all(made.name)
    check(events.size() == 3 and events[1].content == "Canonical", "repeated whole-turn correction is idempotent")
    var file = FileAccess.open(history.path(made.name), FileAccess.READ_WRITE)
    file.seek_end()
    file.store_string("\n   \n\t\n")
    file.close()
    check(history.read_all(made.name) == events, "blank JSONL lines and final EOF do not change replay")
    store.delete_game(made.name)
