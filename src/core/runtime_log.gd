class_name RuntimeLog
extends RefCounted

const Reader = preload("res://src/core/runtime_log_reader.gd")

const DEFAULT_POLICY = {"segment_bytes": 256 * 1024, "session_bytes": 8 * 1024 * 1024, "game_bytes": 32 * 1024 * 1024, "queue_records": 1024, "index_entries": 64}
const MAX_RESPONSE_CHARS = Reader.MAX_RESPONSE_CHARS
var policy = DEFAULT_POLICY.duplicate()
var game_name = ""
var session_id = ""
var root_path = ""
var execution: Dictionary = {}
var session_path = ""
var source_roots: Array[String] = []
var opened_utc = ""
var start_ticks = 0
var load_version = 0 # Successful-load compatibility counter, not diagnostic identity.
var attempt_id = 0
var active_attempt_id = 0
var phase = "idle"
var latest_outcome = "not_loaded"
var seq = 0
var persisted_seq = 0
var processed_seq = 0
var last_notified_seq = 0
var notification_counts = {"error": 0, "warning": 0}
var notification_high = 0
var last_notified_loss = 0
var last_notified_persistence_error = ""
const MAX_NOTICE_RANGES = 1024
const MAX_RECEIPTS = 16
var pending_ranges = {"error": [], "warning": []}
var delivery_receipts: Dictionary = {}
var notification_tracking_compacted = false
var startup_errors: Array[String] = []
var startup_error_count = 0
var capturing_startup = false
var candidate_source_path = ""
var queue: Array[Dictionary] = []
var loss: Array[Dictionary] = []
var loss_totals = {"queue_overflow": 0, "write_failure": 0}
var persistence_error = ""
var segment = 1
var segments: Array[Dictionary] = []
var expired_segments = 0
var oldest_seq = 1
var index: Dictionary = {}
var recovered_sessions = 0
var closed = false
var stopping = false
var mutex = Mutex.new()
var io_mutex = Mutex.new()
var worker: Thread
var writer_thread_id = -1
var collector: CaptureLogger

class CaptureLogger:
    extends Logger
    var target: WeakRef
    func _log_message(message: String, error: bool) -> void:
        var owner = target.get_ref()
        if owner != null:
            owner.capture("error" if error else "info", "godot_message", message)
    func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, type: int, backtraces: Array[ScriptBacktrace]) -> void:
        var owner = target.get_ref()
        if owner == null:
            return
        var trace: Array[Dictionary] = []
        for backtrace in backtraces:
            for frame in range(mini(backtrace.get_frame_count(), 32 - trace.size())):
                trace.append({"file": backtrace.get_frame_file(frame), "line": backtrace.get_frame_line(frame), "function": backtrace.get_frame_function(frame)})
        owner.capture("warning" if type == Logger.ERROR_TYPE_WARNING else "error", "script_error" if type == Logger.ERROR_TYPE_SCRIPT else "godot_error", rationale if rationale != "" else code, file, line, trace, function, true)

func start(name: String, workspace: String, options: Dictionary = {}) -> void:
    if session_id != "":
        return
    policy.merge(options, true)
    game_name = name
    root_path = str(options.get("root_path", "user://host/games".path_join(name).path_join("runtime")))
    execution = options.get("execution", {}).duplicate()
    source_roots.append(workspace.trim_suffix("/") + "/")
    opened_utc = _utc()
    start_ticks = Time.get_ticks_msec()
    session_id = Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "") + "Z-" + Crypto.new().generate_random_bytes(6).hex_encode()
    session_path = root_path.path_join(session_id)
    index = JsonStore.read_dict(root_path.path_join("retention.json"), {"format": 1, "sessions": [], "expired_session_count": 0})
    # Discover sessions whose final index update was interrupted.
    var dir = DirAccess.open(root_path)
    if dir != null:
        for child in dir.get_directories():
            if dir.is_link(child):
                continue
            var found = false
            for entry in index.get("sessions", []):
                if entry.session_id == child:
                    found = true
            if not found:
                var meta = JsonStore.read_dict(root_path.path_join(child).path_join("session.json"), {})
                if not meta.is_empty():
                    index.sessions.append(meta)
    index.sessions = index.sessions.filter(func(entry): return typeof(entry) == TYPE_DICTIONARY and _safe_session(str(entry.get("session_id", ""))))
    for entry in index.sessions:
        if entry.get("status", "") != "expired" and not _closed_session_matches(entry):
            _recover_segments(entry)
    _save_index()
    _start_worker()
    _register()
    add("session_open", "Opened game " + name)

func _recover_segments(meta: Dictionary) -> void:
    recovered_sessions += 1
    var path = root_path.path_join(str(meta.session_id))
    var dir = DirAccess.open(path)
    if dir == null:
        return
    var recovered: Array[Dictionary] = []
    for name in dir.get_files():
        if not name.begins_with("events-") or not name.ends_with(".jsonl"):
            continue
        var f = FileAccess.open(path.path_join(name), FileAccess.READ)
        if f == null:
            continue
        var first = 0
        var last = 0
        while not f.eof_reached():
            var text = f.get_line()
            if text.is_empty():
                continue
            var parser = JSON.new()
            if parser.parse(text) != OK or not Reader.valid_record(parser.data):
                continue
            var value = int(parser.data.seq)
            first = value if first == 0 else mini(first, value)
            last = maxi(last, value)
            var record: Dictionary = parser.data
            meta.latest_attempt = maxi(int(meta.get("latest_attempt", 0)), _number(record.evaluating_attempt))
            meta.active_attempt = maxi(int(meta.get("active_attempt", 0)), int(record.active_attempt))
            if record.attribution == "host_event" and record.kind in ["load", "compile", "startup", "instantiate"] and record.origin_attempt != null:
                meta.latest_attempt = maxi(int(meta.latest_attempt), int(record.origin_attempt))
                meta.latest_outcome = "accepted" if record.severity == "info" else "failed_" + str(record.kind)
        recovered.append({"file": name, "first_seq": first, "last_seq": last, "bytes": f.get_length()})
        f.close()
    recovered.sort_custom(func(a, b): return str(a.file) < str(b.file))
    meta.segments = recovered
    if not recovered.is_empty():
        meta.oldest_seq = int(recovered[0].first_seq)
        meta.persisted_seq = int(recovered[-1].last_seq)
        meta.newest_seq = maxi(int(meta.get("newest_seq", 0)), int(meta.persisted_seq))

func _closed_session_matches(meta: Dictionary) -> bool:
    if meta.get("status", "") != "closed" or str(meta.get("closed_utc", "")) == "":
        return false
    var path = root_path.path_join(str(meta.session_id))
    var disk_meta = JsonStore.read_dict(path.path_join("session.json"), {})
    if disk_meta.get("status", "") != "closed" or disk_meta.get("segments", []) != meta.get("segments", []):
        return false
    var expected: Dictionary = {}
    for segment_meta in meta.get("segments", []):
        var name = str(segment_meta.get("file", ""))
        var file = FileAccess.open(path.path_join(name), FileAccess.READ)
        if file == null:
            return false
        var size = file.get_length()
        file.close()
        if size != int(segment_meta.get("bytes", -1)):
            return false
        expected[name] = true
    var dir = DirAccess.open(path)
    if dir == null:
        return false
    for name in dir.get_files():
        if name.begins_with("events-") and name.ends_with(".jsonl") and not expected.has(name):
            return false
    return true

func _register() -> void:
    collector = CaptureLogger.new()
    collector.target = weakref(self)
    OS.add_logger(collector)

func _start_worker() -> void:
    stopping = false
    worker = Thread.new()
    if worker.start(_write_loop) != OK:
        worker = null
        persistence_error = "Diagnostics writer could not start."

func _write_loop() -> void:
    writer_thread_id = OS.get_thread_caller_id()
    var last_index = 0
    while true:
        _drain()
        mutex.lock()
        var stop = stopping
        mutex.unlock()
        if stop:
            break
        if Time.get_ticks_msec() - last_index > 5000:
            io_mutex.lock()
            _save_index()
            io_mutex.unlock()
            last_index = Time.get_ticks_msec()
        OS.delay_msec(20)

func pause_writer() -> void:
    if collector != null:
        OS.remove_logger(collector)
        collector = null
    mutex.lock()
    stopping = true
    mutex.unlock()
    if worker != null:
        worker.wait_to_finish()
        worker = null
    writer_thread_id = -1
    flush()
    io_mutex.lock()
    _save_index()
    io_mutex.unlock()

func rebind(name: String, workspace: String) -> void:
    var renamed = game_name != name
    game_name = name
    root_path = "user://host/games".path_join(name).path_join("runtime")
    session_path = root_path.path_join(session_id)
    source_roots.append(workspace.trim_suffix("/") + "/")
    _start_worker()
    _register()
    add("game_renamed" if renamed else "writer_rebound", "Diagnostics rebound to " + name)

func close() -> void:
    if closed or session_id == "":
        return
    add("session_close", "Closed game " + game_name)
    mutex.lock()
    closed = true
    mutex.unlock()
    pause_writer()

func begin_attempt(workspace: String) -> int:
    mutex.lock()
    attempt_id += 1
    capturing_startup = true
    candidate_source_path = ""
    startup_errors.clear()
    startup_error_count = 0
    phase = "loading"
    latest_outcome = "evaluating"
    var root = workspace.trim_suffix("/") + "/"
    if root not in source_roots:
        source_roots.append(root)
    var result = attempt_id
    mutex.unlock()
    add("attempt_begin", "Loading " + workspace)
    return result

func set_phase(value: String) -> void:
    mutex.lock()
    phase = value
    mutex.unlock()

func set_candidate_path(path: String) -> void:
    mutex.lock()
    candidate_source_path = path
    mutex.unlock()

func startup_message() -> String:
    mutex.lock()
    var result = "\n".join(startup_errors)
    if startup_error_count > startup_errors.size():
        result += "\nAdditional startup errors: %d" % (startup_error_count - startup_errors.size())
    mutex.unlock()
    return result

func finish_attempt(success: bool, kind: String, message: String) -> Dictionary:
    mutex.lock()
    capturing_startup = false
    if success:
        active_attempt_id = attempt_id
        load_version += 1
    latest_outcome = "accepted" if success else "failed_" + kind
    mutex.unlock()
    capture("info" if success else "error", kind, message, "", 0, [], "", false, "host_event", attempt_id)
    set_phase("running" if active_attempt_id > 0 else "idle")
    var diagnostics = read({"attempt": attempt_id, "limit": 20})
    return {"attempt_id": attempt_id, "active_attempt_id": active_attempt_id, "session_id": session_id, "diagnostics": diagnostics}

func add(kind: String, message: String) -> void:
    capture("info", kind, message, "", 0, [], "", false, "host_event")

func capture(severity: String, kind: String, message: String, file: String = "", line: int = 0, trace: Array = [], function: String = "", engine_error: bool = false, attribution: String = "", origin = null) -> void:
    if message.strip_edges() == "":
        return
    mutex.lock()
    if closed or OS.get_thread_caller_id() == writer_thread_id:
        mutex.unlock()
        return
    seq += 1
    var source = file
    var source_line = line
    for frame in trace:
        if _is_game_source(str(frame.file)):
            source = str(frame.file)
            source_line = int(frame.line)
            break
    if attribution == "":
        attribution = "source_path" if _is_game_source(source) else "active_game_context"
        if source.begins_with("res://src/"):
            attribution = "host_event"
        elif capturing_startup and candidate_source_path != "" and source == candidate_source_path:
            attribution = "candidate_startup"
            origin = attempt_id
    var bounded_trace: Array[Dictionary] = []
    for frame in trace.slice(0, 32):
        bounded_trace.append({"file": str(frame.get("file", "")).left(512), "line": int(frame.get("line", 0)), "function": str(frame.get("function", "")).left(128)})
    var record = {"seq": seq, "utc": _utc(), "elapsed_ms": Time.get_ticks_msec() - start_ticks, "session_id": session_id, "game": game_name, "evaluating_attempt": attempt_id if capturing_startup else null, "active_attempt": active_attempt_id, "origin_attempt": origin, "attribution": attribution, "phase": phase, "severity": severity, "kind": kind, "file": source.left(1024), "source_file": _relative_source(source).left(1024), "line": source_line, "function": function.left(256), "message": message.left(4096), "message_truncated": message.length() > 4096, "trace": bounded_trace, "trace_truncated": trace.size() > 32}
    if not execution.is_empty():
        record.execution = execution
    # Keep synchronous startup acceptance identical to the previous collector.
    if engine_error and capturing_startup and severity == "error":
        startup_error_count += 1
        if startup_errors.size() < 32:
            startup_errors.append("%s:%d: %s" % [source, source_line, message.left(4096)])
    if severity in ["error", "warning"]:
        notification_counts[severity] += 1
        notification_high = seq
        _append_range(pending_ranges[severity], seq)
        if pending_ranges[severity].size() > MAX_NOTICE_RANGES:
            pending_ranges[severity].pop_front()
            notification_tracking_compacted = true
    if queue.size() >= int(policy.queue_records):
        var removed = -1
        if severity != "info":
            for i in range(queue.size()):
                if queue[i].severity == "info":
                    removed = i
                    break
        if removed >= 0:
            var dropped: Dictionary = queue[removed]
            queue.remove_at(removed)
            _loss("queue_overflow", int(dropped.seq), int(dropped.seq), 1)
        else:
            _loss("queue_overflow", seq, seq, 1)
            mutex.unlock()
            return
    queue.append(record)
    mutex.unlock()

func _is_game_source(path: String) -> bool:
    for root in source_roots:
        if path.begins_with(root) or path.begins_with(ProjectSettings.globalize_path(root)):
            return true
    return false

func _relative_source(path: String) -> String:
    for root in source_roots:
        for prefix in [root, ProjectSettings.globalize_path(root)]:
            if path.begins_with(prefix):
                return path.trim_prefix(prefix).split("#candidate-")[0]
    return ""

func _loss(kind: String, first: int, last: int, count: int) -> void:
    loss_totals[kind] += count
    if not loss.is_empty() and loss[-1].kind == kind and int(loss[-1].last_seq) + 1 == first:
        loss[-1].last_seq = last
        loss[-1].count += count
    else:
        loss.append({"kind": kind, "first_seq": first, "last_seq": last, "count": count})
    if loss.size() > 64:
        loss.pop_front() # Lifetime totals survive compaction of exact recent ranges.

func flush() -> void:
    mutex.lock()
    var target = seq
    mutex.unlock()
    if worker == null:
        _drain()
        return
    # The same serialization lock guards draining and reads. No callback takes it.
    while true:
        io_mutex.lock()
        mutex.lock()
        var empty = processed_seq >= target
        mutex.unlock()
        io_mutex.unlock()
        if empty:
            return
        OS.delay_msec(1)

func _drain() -> void:
    io_mutex.lock()
    mutex.lock()
    var batch = queue
    queue = []
    var target = seq
    mutex.unlock()
    if not batch.is_empty():
        var mkdir_error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(session_path))
        var f: FileAccess
        var current_file = ""
        var written: Array[Dictionary] = []
        var position = 0
        for record in batch:
            var bytes = (JSON.stringify(record) + "\n").to_utf8_buffer()
            if not segments.is_empty() and int(segments[-1].bytes) > 0 and int(segments[-1].bytes) + bytes.size() > int(policy.segment_bytes):
                segment += 1
            var file_name = "events-%04d.jsonl" % segment
            if segments.is_empty() or segments[-1].file != file_name:
                segments.append({"file": file_name, "first_seq": record.seq, "last_seq": record.seq, "bytes": 0})
            var path = session_path.path_join(file_name)
            if path != current_file:
                if f != null:
                    _finish_batch_file(f, written, position)
                written = []
                f = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE) if mkdir_error in [OK, ERR_ALREADY_EXISTS] else null
                current_file = path
                if f != null:
                    f.seek_end()
                    position = f.get_position()
            if f != null:
                f.store_buffer(bytes)
                written.append(record)
                segments[-1].bytes += bytes.size()
                segments[-1].last_seq = record.seq
            else:
                mutex.lock()
                persistence_error = "Diagnostics event write failed: " + path
                _loss("write_failure", int(record.seq), int(record.seq), 1)
                mutex.unlock()
        if f != null:
            _finish_batch_file(f, written, position)
        _enforce_session_budget()
    mutex.lock()
    processed_seq = target
    mutex.unlock()
    io_mutex.unlock()

func _finish_batch_file(file: FileAccess, records: Array, position: int) -> void:
    file.flush()
    var ok = file.get_error() == OK
    if not ok:
        file.resize(position)
    file.close()
    mutex.lock()
    if ok and not records.is_empty():
        persisted_seq = int(records[-1].seq)
    elif not ok:
        persistence_error = "Diagnostics batch write or flush failed."
        for record in records:
            _loss("write_failure", int(record.seq), int(record.seq), 1)
    mutex.unlock()

func _enforce_session_budget() -> void:
    var bytes = _bytes(segments)
    while bytes > int(policy.session_bytes) and segments.size() > 1:
        var old: Dictionary = segments[0]
        if DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path.path_join(old.file))) != OK:
            _metadata_failure("Could not expire diagnostics segment " + str(old.file))
            break
        bytes -= int(old.bytes)
        segments.pop_front()
        expired_segments += 1
        oldest_seq = int(old.last_seq) + 1

func _metadata_failure(message: String) -> void:
    mutex.lock()
    persistence_error = message
    mutex.unlock()

func _session_meta() -> Dictionary:
    mutex.lock()
    var range_count = 0
    for item in loss:
        range_count += int(item.count)
    var result = {"format": 1, "session_id": session_id, "game": game_name, "opened_utc": opened_utc, "closed_utc": _utc() if closed else "", "status": "closed" if closed else "open", "oldest_seq": oldest_seq, "newest_seq": seq, "persisted_seq": persisted_seq, "latest_attempt": attempt_id, "active_attempt": active_attempt_id, "latest_outcome": latest_outcome, "segments": segments.duplicate(true), "expired_segments": expired_segments, "retention_reason": "session_storage_budget" if expired_segments > 0 else "", "loss": loss.duplicate(true), "loss_totals": loss_totals.duplicate(), "loss_ranges_complete": range_count == int(loss_totals.queue_overflow) + int(loss_totals.write_failure), "persistence_error": persistence_error}
    if not execution.is_empty():
        result.execution = execution
    mutex.unlock()
    return result

func _save_index() -> void:
    var meta = _session_meta()
    if not JsonStore.write_dict(session_path.path_join("session.json"), meta):
        _metadata_failure("Diagnostics session metadata write failed.")
    var found = false
    for i in range(index.get("sessions", []).size()):
        if index.sessions[i].session_id == session_id:
            index.sessions[i] = meta
            found = true
    if not found:
        index.sessions.append(meta)
    index.sessions.sort_custom(func(a, b): return str(a.opened_utc) < str(b.opened_utc) if a.opened_utc != b.opened_utc else str(a.session_id) < str(b.session_id))
    var total = 0
    var retained = 0
    for entry in index.sessions:
        if entry.status != "expired":
            total += _bytes(entry.get("segments", []))
            retained += 1
    for entry in index.sessions:
        if total <= int(policy.game_bytes) and retained <= int(policy.index_entries):
            break
        if entry.session_id == session_id or entry.status == "expired":
            continue
        var old_path = root_path.path_join(str(entry.session_id))
        var dir = DirAccess.open(old_path)
        var removed = true
        if dir != null:
            for file in dir.get_files():
                if (file.begins_with("events-") and file.ends_with(".jsonl")) or file == "session.json":
                    if DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path.path_join(file))) != OK:
                        removed = false
            if removed:
                removed = DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path)) == OK
        if removed:
            total -= _bytes(entry.get("segments", []))
            retained -= 1
            entry.status = "expired"
            entry.expired_utc = _utc()
            entry.reason = "game_storage_budget"
            entry.segments = []
        else:
            _metadata_failure("Could not expire old diagnostics session.")
    while index.sessions.size() > int(policy.index_entries):
        var tombstone = -1
        for i in range(index.sessions.size()):
            if index.sessions[i].status == "expired":
                tombstone = i
                break
        if tombstone < 0:
            break
        index.expired_session_count = int(index.get("expired_session_count", 0)) + 1
        index.compacted_through_session = index.sessions[tombstone].session_id
        index.sessions.remove_at(tombstone)
    if not JsonStore.write_dict(root_path.path_join("retention.json"), index):
        _metadata_failure("Diagnostics retention index write failed.")

func read(options: Dictionary = {}, delivered_to_pi: bool = false) -> Dictionary:
    flush()
    io_mutex.lock()
    var selected = str(options.get("session_id", session_id))
    var meta = _session_meta() if selected == session_id else {}
    if selected != session_id:
        for entry in index.get("sessions", []):
            if entry.session_id == selected:
                meta = entry.duplicate(true)
                break
    var sessions: Array[Dictionary] = []
    for entry in index.get("sessions", []):
        sessions.append({"session_id": entry.session_id, "status": entry.status})
    if meta.is_empty() or meta.get("status", "") == "expired":
        io_mutex.unlock()
        return {"ok": false, "error": "session_unavailable", "session_id": selected, "retention": meta, "sessions": sessions, "expired_session_count": index.get("expired_session_count", 0), "compacted_through_session": index.get("compacted_through_session", "")}
    var cursor = maxi(0, int(options.get("cursor", 0)))
    if cursor > 0 and cursor + 1 < int(meta.oldest_seq):
        io_mutex.unlock()
        return {"ok": false, "error": "cursor_expired", "oldest_available_seq": meta.oldest_seq, "session_id": selected, "retention": meta}
    var snapshot = Reader.read_segments(root_path, selected, meta, options)
    io_mutex.unlock()
    var presentation = Reader.format_response(snapshot.records, meta, sessions, snapshot.read_errors, options)
    var result: Dictionary = presentation.response
    var members: Dictionary = presentation.members
    if selected == session_id and delivered_to_pi:
        var ranges = {"error": [], "warning": []}
        for record in result.records:
            if record.severity not in ranges:
                continue
            var exact: Array = members.get(int(record.seq), [[int(record.seq), int(record.seq)]])
            for interval in exact:
                if ranges[record.severity].size() < MAX_NOTICE_RANGES:
                    ranges[record.severity].append(interval)
        result.delivery_id = _receipt({"kind": "records", "ranges": ranges})
    return result

func read_text() -> String:
    return str(read().get("log", ""))

func prepare_notification() -> Dictionary:
    mutex.lock()
    var errors = int(notification_counts.error)
    var warnings = int(notification_counts.warning)
    var result = ""
    if errors + warnings > 0:
        result = "GameSmith diagnostics: %d new errors and %d new warnings in session %s through seq %d (active attempt %d, latest attempt %d). This notice covers counts, not contents. Use read_runtime_log for evidence." % [errors, warnings, session_id, notification_high, active_attempt_id, attempt_id]
        if notification_tracking_compacted:
            result += " Some delivery tracking was compacted; counts may conservatively include previously returned evidence."
    var lost = int(loss_totals.queue_overflow) + int(loss_totals.write_failure)
    if lost > last_notified_loss:
        result += "\nDiagnostics evidence has gaps: %d queue-overflow records and %d failed writes in this session. Use read_runtime_log for loss ranges and persistence status." % [loss_totals.queue_overflow, loss_totals.write_failure]
    if persistence_error != "" and persistence_error != last_notified_persistence_error:
        result += "\nDiagnostics persistence degraded: " + persistence_error
    var receipt = {"kind": "notice", "counts": notification_counts.duplicate(), "high": notification_high, "lost": lost, "persistence_error": persistence_error}
    mutex.unlock()
    return {"ok": true, "notice": result, "delivery_id": _receipt(receipt)}

func take_notification() -> String:
    var result = prepare_notification()
    commit_delivery(result.delivery_id)
    return result.notice

func _receipt(value: Dictionary) -> String:
    var id = Crypto.new().generate_random_bytes(12).hex_encode()
    mutex.lock()
    delivery_receipts[id] = value
    if delivery_receipts.size() > MAX_RECEIPTS:
        delivery_receipts.erase(delivery_receipts.keys()[0])
    mutex.unlock()
    return id

func commit_delivery(id: String) -> void:
    mutex.lock()
    var receipt: Dictionary = delivery_receipts.get(id, {})
    delivery_receipts.erase(id)
    if receipt.is_empty():
        mutex.unlock()
        return
    if receipt.kind == "notice":
        if int(receipt.high) >= last_notified_seq:
            for severity in pending_ranges:
                _remove_delivered(severity, [[0, int(receipt.high)]], false)
                var count = mini(int(notification_counts[severity]), int(receipt.counts[severity]))
                notification_counts[severity] -= count
                _adjust_notice_receipts(severity, count, int(receipt.high))
            last_notified_seq = int(receipt.high)
            notification_tracking_compacted = false
        last_notified_loss = maxi(last_notified_loss, int(receipt.lost))
        last_notified_persistence_error = receipt.persistence_error
    else:
        for severity in pending_ranges:
            for removed in _remove_delivered(severity, receipt.ranges[severity], true):
                for pending in delivery_receipts.values():
                    if pending.kind == "notice":
                        var count = maxi(0, mini(int(removed[1]), int(pending.high)) - int(removed[0]) + 1)
                        pending.counts[severity] = maxi(0, int(pending.counts[severity]) - count)
    mutex.unlock()

func _adjust_notice_receipts(severity: String, count: int, high: int) -> void:
    for pending in delivery_receipts.values():
        if pending.kind == "notice" and int(pending.high) >= high:
            pending.counts[severity] = maxi(0, int(pending.counts[severity]) - count)

func _remove_delivered(severity: String, delivered: Array, decrement: bool) -> Array:
    var removed: Array = []
    for exact in delivered:
        var remaining: Array = []
        for interval in pending_ranges[severity]:
            var first = maxi(int(interval[0]), int(exact[0]))
            var last = mini(int(interval[1]), int(exact[1]))
            if first > last:
                remaining.append(interval)
                continue
            removed.append([first, last])
            if decrement:
                notification_counts[severity] -= last - first + 1
            if int(interval[0]) < first:
                remaining.append([int(interval[0]), first - 1])
            if last < int(interval[1]):
                remaining.append([last + 1, int(interval[1])])
        while remaining.size() > MAX_NOTICE_RANGES:
            remaining.pop_front()
            notification_tracking_compacted = true
        pending_ranges[severity] = remaining
    return removed

static func _append_range(ranges: Array, value: int) -> void:
    if not ranges.is_empty() and int(ranges[-1][1]) + 1 == value:
        ranges[-1][1] = value
    else:
        ranges.append([value, value])

static func _bytes(items: Array) -> int:
    var total = 0
    for item in items:
        total += int(item.bytes)
    return total

static func _number(value) -> int:
    return 0 if value == null else int(value)

static func _safe_session(value: String) -> bool:
    if value.is_empty() or value.length() > 64:
        return false
    for character in value:
        if character not in "0123456789TZ-abcdef":
            return false
    return true

static func _utc() -> String:
    var now = Time.get_unix_time_from_system()
    return Time.get_datetime_string_from_unix_time(int(now)) + ".%03dZ" % int(fmod(now, 1.0) * 1000)
