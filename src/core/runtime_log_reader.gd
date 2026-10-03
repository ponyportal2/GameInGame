extends RefCounted

# Query and presentation only. RuntimeLog owns session state, I/O locking and
# delivery receipts; exact group membership stays private until final trimming.
const MAX_RESPONSE_CHARS = 12000

static func read_segments(root_path: String, selected: String, meta: Dictionary, options: Dictionary) -> Dictionary:
    var cursor = maxi(0, int(options.get("cursor", 0)))
    var records: Array[Dictionary] = []
    var damaged: Array[String] = []
    for item in meta.get("segments", []):
        var f = FileAccess.open(root_path.path_join(selected).path_join(str(item.file)), FileAccess.READ)
        if f == null:
            damaged.append("unreadable_segment: " + str(item.file))
            continue
        while not f.eof_reached():
            var text = f.get_line()
            if text.is_empty():
                continue
            var parser = JSON.new()
            var parsed = parser.parse(text)
            var record = parser.data
            if parsed != OK or not valid_record(record):
                if damaged.size() < 16:
                    damaged.append("invalid_or_partial_record: " + str(item.file))
                continue
            if int(record.seq) <= cursor:
                continue
            if options.has("severity") and record.severity != options.severity:
                continue
            if options.has("attempt") and _number(record.get("evaluating_attempt")) != int(options.attempt) and _number(record.get("origin_attempt")) != int(options.attempt) and not (record.get("evaluating_attempt") == null and int(record.active_attempt) == int(options.attempt)):
                continue
            records.append(record)
        f.close()
    return {"records": records, "read_errors": damaged}

static func format_response(records: Array[Dictionary], meta: Dictionary, sessions: Array[Dictionary], damaged: Array[String], options: Dictionary) -> Dictionary:
    var selected = str(meta.session_id)
    var cursor = maxi(0, int(options.get("cursor", 0)))
    var limit = clampi(int(options.get("limit", 30)), 1, 100)
    var raw = bool(options.get("raw", false)) or options.has("cursor")
    var output: Array = []
    var members: Dictionary = {}
    var more = false
    if raw:
        output = records.slice(0, limit)
        more = records.size() > output.size()
    else:
        var groups: Dictionary = {}
        for record in records:
            if record.severity == "info" and record.kind not in ["load", "compile", "startup", "instantiate"]:
                continue
            var key = JSON.stringify([record.severity, record.kind, record.file, record.line, record.message, record.evaluating_attempt, record.active_attempt, record.origin_attempt])
            if groups.has(key):
                groups[key].count += 1
                groups[key].last_seq = record.seq
                groups[key].last_elapsed_ms = record.elapsed_ms
                _append_range(members[int(groups[key].seq)], int(record.seq))
            else:
                var group = record.duplicate(true)
                group.count = 1
                group.last_seq = record.seq
                group.last_elapsed_ms = record.elapsed_ms
                groups[key] = group
                members[int(group.seq)] = [[int(record.seq), int(record.seq)]]
        output = groups.values()
        output.sort_custom(func(a, b):
            var rank_a = 0 if a.kind in ["compile", "startup", "instantiate", "load"] and _number(a.get("origin_attempt")) == int(meta.latest_attempt) else (1 if a.severity == "error" else 2)
            var rank_b = 0 if b.kind in ["compile", "startup", "instantiate", "load"] and _number(b.get("origin_attempt")) == int(meta.latest_attempt) else (1 if b.severity == "error" else 2)
            return rank_a < rank_b if rank_a != rank_b else int(a.last_seq) > int(b.last_seq))
        more = output.size() > limit
        output = output.slice(0, limit)
        if output.is_empty():
            output = records.slice(maxi(0, records.size() - mini(limit, 5)))
    var size = 0
    var bounded: Array[Dictionary] = []
    for record in output:
        record = record.duplicate(true)
        if JSON.stringify(record).length() > 6000:
            record.trace = record.trace.slice(0, 4)
            record.message = str(record.message).left(2000)
            record.response_truncated = true
        var length = JSON.stringify(record).length()
        if size + length > MAX_RESPONSE_CHARS - 2500:
            more = true
            break
        bounded.append(record)
        size += length
    var next = cursor if bounded.is_empty() else int(bounded[-1].seq)
    var lines: Array[String] = ["Session: %s | active attempt: %s | latest attempt: %s (%s)" % [selected, meta.active_attempt, meta.latest_attempt, meta.latest_outcome]]
    for record in bounded:
        lines.append("[seq %s][%s][evaluating %s / active %s / origin %s]%s %s:%s %s" % [record.seq, record.severity, record.evaluating_attempt, record.active_attempt, record.origin_attempt, " x%d" % int(record.count) if int(record.get("count", 1)) > 1 else "", record.get("source_file", "") if record.get("source_file", "") != "" else record.file, record.line, record.message])
    var result = {"ok": true, "session_id": selected, "active_attempt_id": meta.active_attempt, "latest_attempt_id": meta.latest_attempt, "latest_outcome": meta.latest_outcome, "records": bounded, "log": "\n".join(lines).left(MAX_RESPONSE_CHARS), "next_cursor": next if raw else null, "has_more": more or (not raw and records.size() > bounded.size()), "oldest_available_seq": meta.oldest_seq, "newest_captured_seq": meta.newest_seq, "persisted_seq": meta.persisted_seq, "loss": meta.loss, "loss_totals": meta.loss_totals, "loss_ranges_complete": meta.loss_ranges_complete, "expired_segments": meta.expired_segments, "persistence_error": meta.persistence_error, "read_errors": damaged, "sessions": sessions, "pagination": "Use raw=true and cursor=0 for chronological records; cursor is exclusive and session-scoped."}
    if JSON.stringify(result).length() > MAX_RESPONSE_CHARS:
        # Records are the evidence; avoid duplicating their full text in log.
        result.log = lines[0]
        result.loss = result.loss.slice(maxi(0, result.loss.size() - 16))
        result.sessions = result.sessions.slice(maxi(0, result.sessions.size() - 16))
        result.bookkeeping_truncated = true
    # Preserve the response budget including bookkeeping and the text view.
    while JSON.stringify(result).length() > MAX_RESPONSE_CHARS - 128 and not result.records.is_empty():
        result.records.pop_back()
        result.has_more = true
        result.log = "\n".join(lines.slice(0, result.records.size() + 1))
        result.next_cursor = (cursor if result.records.is_empty() else int(result.records[-1].seq)) if raw else null
    return {"response": result, "members": members}

static func valid_record(record) -> bool:
    if typeof(record) != TYPE_DICTIONARY:
        return false
    for field in ["seq", "utc", "elapsed_ms", "session_id", "evaluating_attempt", "active_attempt", "origin_attempt", "phase", "severity", "kind", "file", "line", "message", "trace"]:
        if not record.has(field):
            return false
    return typeof(record.seq) in [TYPE_FLOAT, TYPE_INT] and typeof(record.message) == TYPE_STRING and typeof(record.trace) == TYPE_ARRAY

static func _append_range(ranges: Array, value: int) -> void:
    if not ranges.is_empty() and int(ranges[-1][1]) + 1 == value:
        ranges[-1][1] = value
    else:
        ranges.append([value, value])

static func _number(value) -> int:
    return 0 if value == null else int(value)
