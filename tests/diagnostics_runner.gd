extends SceneTree

const Log = preload("res://src/core/runtime_log.gd")
const Runner = preload("res://src/core/game_runner.gd")
const Store = preload("res://src/core/workspace_store.gd")
const Json = preload("res://src/core/json_store.gd")
var passed = 0
var failures = 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, label: String) -> void:
    if value:
        passed += 1
        print("PASS: ", label)
    else:
        failures += 1
        push_error("FAIL: " + label)

func put(path: String, value: String) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var f = FileAccess.open(path, FileAccess.WRITE)
    f.store_string(value)
    f.close()

func has_message(result: Dictionary, message: String) -> bool:
    for record in result.get("records", []):
        if message in str(record.message):
            return true
    return false

func run() -> void:
    await test_capture()
    test_overflow()
    test_concurrent_capture()
    test_retention_failure_recovery()
    await test_rename_fallback()
    print("DIAGNOSTICS TESTS: %d passed, %d failed" % [passed, failures])
    quit(0 if failures == 0 else 1)

func test_capture() -> void:
    var created = Store.new().create_game("Diagnostics Capture")
    var runner = Runner.new()
    root.add_child(runner)
    put(created.path.path_join("main.gd"), "extends Node\nfunc _ready():\n    print('startup print')\n    push_warning('startup warning')\n")
    var result = runner.load_game(created.path)
    check(result.ok and result.attempt_id == 1 and result.active_attempt_id == 1, "successful candidate has independent attempt identity")
    check(has_message(result.diagnostics, "startup warning"), "reload result includes actual Godot startup warnings")
    print("live diagnostic print")
    push_warning("live diagnostic warning")
    push_error("live diagnostic error")
    var raw = runner.runtime_log.read({"raw": true, "limit": 100})
    check(has_message(raw, "startup print") and has_message(raw, "live diagnostic print"), "persistent logger captures startup and later prints")
    check(has_message(raw, "live diagnostic warning") and has_message(raw, "live diagnostic error"), "persistent logger captures later warnings and errors")
    var ordered = true
    var timed = true
    var previous = 0
    var ambiguous = false
    for record in raw.records:
        timed = timed and str(record.utc).ends_with("Z") and "." in str(record.utc) and int(record.elapsed_ms) >= 0
        ordered = ordered and int(record.seq) > previous
        previous = int(record.seq)
        if str(record.message).strip_edges() == "live diagnostic print":
            ambiguous = record.origin_attempt == null and record.attribution == "active_game_context"
    check(timed and ordered, "records have UTC milliseconds, elapsed time and ordered capture sequences")
    check(ambiguous, "ordinary print never claims known origin")
    var old = runner.active_game
    put(created.path.path_join("main.gd"), "extends Node\nfunc broken(:\n")
    var failed = runner.load_game(created.path)
    check(not failed.ok and failed.attempt_id == 2 and failed.active_attempt_id == 1 and runner.active_game == old, "compile failure belongs to attempt 2 while attempt 1 stays active")
    check(has_message(failed.diagnostics, "Expected parameter"), "compile result contains captured error evidence")
    put(created.path.path_join("main.gd"), "extends Node\nfunc _ready():\n    var x = []\n    print(x[42])\n")
    var startup = runner.load_game(created.path)
    check(not startup.ok and startup.attempt_id == 3 and runner.active_game == old and startup.diagnostics.latest_outcome == "failed_startup", "startup acceptance policy remains unchanged")
    var id = runner.runtime_log.session_id
    var directory = runner.runtime_log.session_path
    runner.queue_free()
    await process_frame
    check(Json.read_dict(directory.path_join("session.json")).status == "closed", "closing runner drains writer and closes session")
    var reopened = Log.new()
    reopened.start(created.name, created.path)
    check(reopened.session_id != id, "reopening creates new session")
    var history = reopened.read({"session_id": id, "severity": "error", "raw": true})
    check(history.ok and not history.records.is_empty(), "earlier session evidence stays readable")
    reopened.close()
    Store.new().delete_game(created.name)

func test_overflow() -> void:
    var log = Log.new()
    log.start("Diagnostics Overflow", "user://games/Diagnostics Overflow", {"queue_records": 8})
    log.pause_writer()
    for i in range(20):
        log.capture("info", "print", "noise %d" % i)
    log.capture("error", "script_error", "important error", "enemy.gd", 42)
    log.capture("warning", "godot_error", "important warning")
    var data = log.read({"raw": true, "limit": 100}, true)
    check(int(data.loss_totals.queue_overflow) > 0 and not data.loss.is_empty(), "queue overflow reports capture-time sequence gaps")
    check(has_message(data, "important error") and has_message(data, "important warning"), "pressure drops ordinary output before important diagnostics")
    log.capture("error", "script_error", "unread error")
    log.capture("warning", "godot_error", "read warning")
    log.read({"severity": "warning", "raw": true}, true)
    var notice = log.take_notification()
    check("1 new errors and 0 new warnings" in notice, "filtered warning read cannot suppress an omitted error: " + notice)
    check(log.take_notification() == "", "aggregate notification occurs once")
    log.capture("info", "print", "ordinary print")
    check(log.take_notification() == "", "prints never trigger hints")
    for i in range(4):
        log.capture("error", "script_error", "repeated failure", "enemy.gd", 12)
    var summary = log.read()
    var count = 0
    for record in summary.records:
        if record.message == "repeated failure":
            count = int(record.count)
    check(count == 4, "duplicates collapse only in presentation")
    var first = log.read({"raw": true, "cursor": 0, "limit": 2})
    var second = log.read({"raw": true, "cursor": first.next_cursor, "limit": 2})
    check(first.has_more and second.records[0].seq > first.records[-1].seq, "exclusive cursor paginates chronological evidence")
    check(JSON.stringify(summary).length() <= Log.MAX_RESPONSE_CHARS, "whole response respects context budget")
    log.begin_attempt("user://games/Diagnostics Overflow")
    log.set_candidate_path("user://games/Diagnostics Overflow/main.gd#candidate-new")
    log.capture("error", "script_error", "old instance during reload", "user://games/Diagnostics Overflow/main.gd#candidate-old", 4)
    var uncertain = log.read({"severity": "error", "raw": true, "cursor": int(log.seq) - 1})
    check(uncertain.records[0].origin_attempt == null and uncertain.records[0].attribution == "source_path", "old active instance cannot be misattributed to a new candidate")
    log.close()
    Store.new().metadata.delete_game("Diagnostics Overflow")

func emit_records(log, prefix: String) -> void:
    for i in range(30):
        log.capture("info", "print", "%s %d" % [prefix, i])

func test_concurrent_capture() -> void:
    var log = Log.new()
    log.start("Diagnostics Threads", "user://games/Diagnostics Threads")
    log.pause_writer()
    var threads: Array[Thread] = []
    for i in range(3):
        var thread = Thread.new()
        thread.start(emit_records.bind(log, "thread%d" % i))
        threads.append(thread)
    for thread in threads:
        thread.wait_to_finish()
    var captured = 0
    var previous = 0
    var ordered = true
    while true:
        var page = log.read({"raw": true, "cursor": previous, "limit": 100})
        for record in page.records:
            ordered = ordered and int(record.seq) > previous
            previous = int(record.seq)
            if str(record.message).begins_with("thread"):
                captured += 1
        if not page.has_more or page.records.is_empty():
            break
    check(ordered and captured == 90, "concurrent callback capture preserves unique sequence order across pages")
    log.capture("error", "script_error", "survives a print flood")
    log.flush()
    for i in range(500):
        log.capture("info", "print", "flood %d" % i)
    check(has_message(log.read(), "survives a print flood"), "default summary preserves earlier errors across a print flood")
    log.close()
    Store.new().metadata.delete_game("Diagnostics Threads")

func test_retention_failure_recovery() -> void:
    var log = Log.new()
    log.start("Diagnostics Retention", "user://games/Diagnostics Retention", {"segment_bytes": 1500, "session_bytes": 3000, "game_bytes": 4000, "index_entries": 3})
    log.pause_writer()
    for i in range(12):
        log.capture("info", "print", "segment %d " % i + "x".repeat(200))
    var data = log.read({"raw": true})
    check(data.expired_segments > 0 and data.oldest_available_seq > 1, "session retention reports segment expiration")
    var expired = log.read({"cursor": 1})
    check(not expired.ok and expired.error == "cursor_expired", "expired cursor fails explicitly")
    var old_id = log.session_id
    log.close()
    var next = Log.new()
    next.start("Diagnostics Retention", "user://games/Diagnostics Retention", {"game_bytes": 1000, "index_entries": 3})
    next.pause_writer()
    var old = next.read({"session_id": old_id})
    check(not old.ok and old.retention.status == "expired", "game retention keeps surviving expired-session tombstone")
    next.close()
    var fail = Log.new()
    fail.start("Diagnostics Failure", "user://games/Diagnostics Failure")
    fail.pause_writer()
    var original = fail.session_path
    var blocker = fail.root_path.path_join("blocker")
    put(blocker, "not a directory")
    fail.session_path = blocker.path_join("session")
    fail.capture("error", "script_error", "cannot persist")
    var degraded = fail.read()
    check(degraded.loss_totals.write_failure > 0 and degraded.persistence_error != "", "write failure stays visible in memory")
    fail.session_path = original
    fail.close()
    check(Json.read_dict(original.path_join("session.json")).loss_totals.write_failure > 0, "write failure history survives storage recovery")
    var recovery = Log.new()
    recovery.start("Diagnostics Recovery", "user://games/Diagnostics Recovery")
    recovery.pause_writer()
    recovery.capture("warning", "godot_error", "recover me")
    recovery.close()
    var path = recovery.session_path.path_join(recovery.segments[-1].file)
    var f = FileAccess.open(path, FileAccess.READ_WRITE)
    f.seek_end()
    f.store_string('{"seq":999,"message":')
    f.close()
    var reopened = Log.new()
    reopened.start("Diagnostics Recovery", "user://games/Diagnostics Recovery")
    var readback = reopened.read({"session_id": recovery.session_id, "raw": true})
    check(readback.ok and has_message(readback, "recover me") and not readback.read_errors.is_empty(), "interrupted JSONL tail reports damage and preserves intact evidence")
    reopened.close()
    for name in ["Diagnostics Retention", "Diagnostics Failure", "Diagnostics Recovery"]:
        Store.new().metadata.delete_game(name)

func test_rename_fallback() -> void:
    var store = Store.new()
    var created = store.create_game("Diagnostics Rename")
    var runner = Runner.new()
    root.add_child(runner)
    put(created.path.path_join("main.gd"), "extends Node\n")
    runner.load_game(created.path)
    store.save_working_snapshot(created.name)
    var id = runner.runtime_log.session_id
    runner.runtime_log.pause_writer()
    var renamed = store.rename_game(created.name, "Diagnostics Renamed")
    var renamed_path = store.game_path(renamed.name)
    runner.runtime_log.rebind(renamed.name, renamed_path)
    runner.runtime_log.capture("warning", "godot_error", "after rename")
    var data = runner.runtime_log.read()
    check(renamed.ok and data.session_id == id and has_message(data, "after rename"), "Windows rename rebinds writer and preserves session")
    put(renamed_path.path_join("main.gd"), "extends Node\nfunc broken(:\n")
    var broken = runner.load_game(renamed_path)
    var fallback = runner.load_game(store.metadata.snapshot_dir(renamed.name))
    check(not broken.ok and fallback.ok and broken.attempt_id + 1 == fallback.attempt_id and fallback.active_attempt_id == fallback.attempt_id, "workspace failure and snapshot fallback have separate attempts")
    runner.queue_free()
    await process_frame
    store.delete_game(renamed.name)
