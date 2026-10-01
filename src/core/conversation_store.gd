class_name ConversationStore
extends RefCounted

const VERIFICATION_PREFIX = "GameSmith verification rejected that completion:"
const COMPACTION_SUMMARY_PREFIX = "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"
const COMPACTION_SUMMARY_SUFFIX = "\n</summary>"

var metadata = MetadataStore.new()

func exists(game_name: String) -> bool:
    return FileAccess.file_exists(metadata.conversation_path(game_name))

func append(game_name: String, message: Dictionary) -> bool:
    return JsonStore.append_json_line(metadata.conversation_path(game_name), message)

func append_compaction(game_name: String, summary: String, first_kept_message_index: int, tokens_before: int, details: Dictionary = {}) -> bool:
    return JsonStore.append_json_line(metadata.conversation_path(game_name), {
        "type": "compaction",
        "summary": summary,
        "first_kept_message_index": first_kept_message_index,
        "tokens_before": tokens_before,
        "details": details,
        "time": Time.get_datetime_string_from_system(true)
    })

func read_entries(game_name: String) -> Array:
    var path = metadata.conversation_path(game_name)
    var out: Array = []
    if not FileAccess.file_exists(path):
        return out
    var file = FileAccess.open(path, FileAccess.READ)
    while file != null and not file.eof_reached():
        var line = file.get_line().strip_edges()
        if line == "":
            continue
        var parsed = JSON.parse_string(line)
        if typeof(parsed) == TYPE_DICTIONARY:
            out.append(parsed)
    return out

func read_all(game_name: String) -> Array:
    var out: Array = []
    for entry in read_entries(game_name):
        if str(entry.get("type", "")) == "compaction":
            continue
        if entry.has("role"):
            out.append(entry)
    return out

func read_for_provider(game_name: String) -> Array:
    var state = context_state(game_name)
    var out: Array = []
    var summary = str(state.get("previous_summary", ""))
    if summary != "":
        out.append({"role": "user", "content": COMPACTION_SUMMARY_PREFIX + summary + COMPACTION_SUMMARY_SUFFIX})
    out.append_array(state.get("messages", []))
    return out

func context_state(game_name: String) -> Dictionary:
    var entries = read_entries(game_name)
    var latest_compaction: Dictionary = {}
    var raw_pairs: Array = []
    var message_index = 0
    for entry in entries:
        if str(entry.get("type", "")) == "compaction":
            latest_compaction = entry
            continue
        if not entry.has("role"):
            continue
        raw_pairs.append({"index": message_index, "message": entry})
        message_index += 1

    var cleaned: Array = []
    for pair in raw_pairs:
        var message: Dictionary = pair.message
        if _is_verification_message(message):
            if not cleaned.is_empty():
                var previous: Dictionary = cleaned[-1].message
                if str(previous.get("role", "")) == "assistant" and not previous.has("tool_calls"):
                    cleaned.pop_back()
            continue
        cleaned.append(pair)

    var boundary = int(latest_compaction.get("first_kept_message_index", 0))
    var messages: Array = []
    var indexes: Array = []
    for pair in cleaned:
        if int(pair.index) < boundary:
            continue
        messages.append(pair.message)
        indexes.append(int(pair.index))

    return {
        "messages": messages,
        "indexes": indexes,
        "boundary_start_message_index": boundary,
        "raw_message_count": message_index,
        "previous_summary": str(latest_compaction.get("summary", "")),
        "previous_details": latest_compaction.get("details", {}),
        "latest_compaction": latest_compaction
    }

func estimate_provider_tokens(game_name: String) -> int:
    return estimate_messages_tokens(read_for_provider(game_name))

func estimate_messages_tokens(messages: Array) -> int:
    var total = 0
    for message in messages:
        total += _estimate_message_tokens(message)
    return total

func prepare_compaction(game_name: String, keep_recent_tokens: int) -> Dictionary:
    var state = context_state(game_name)
    var messages: Array = state.messages
    var indexes: Array = state.indexes
    if messages.is_empty():
        return {"ok": false, "no_op": true, "error": "Conversation is empty."}

    var cut_points: Array[int] = []
    for i in messages.size():
        var role = str(messages[i].get("role", ""))
        if role == "user" or role == "assistant":
            cut_points.append(i)
    if cut_points.is_empty():
        return {"ok": false, "no_op": true, "error": "No valid compaction cut point."}

    var budget = maxi(1, keep_recent_tokens)
    var accumulated = 0
    var cut_index = cut_points[0]
    for i in range(messages.size() - 1, -1, -1):
        accumulated += _estimate_message_tokens(messages[i])
        if accumulated >= budget:
            cut_index = cut_points[-1]
            for candidate in cut_points:
                if candidate >= i:
                    cut_index = candidate
                    break
            break

    var starts_turn = str(messages[cut_index].get("role", "")) == "user"
    var turn_start = -1
    if not starts_turn:
        for i in range(cut_index, -1, -1):
            if str(messages[i].get("role", "")) == "user":
                turn_start = i
                break
    var is_split_turn = not starts_turn and turn_start >= 0
    var history_end = turn_start if is_split_turn else cut_index
    var messages_to_summarize: Array = messages.slice(0, history_end)
    var turn_prefix_messages: Array = messages.slice(turn_start, cut_index) if is_split_turn else []
    if messages_to_summarize.is_empty() and turn_prefix_messages.is_empty():
        return {"ok": false, "no_op": true, "error": "Conversation is already within the recent-token budget."}

    return {
        "ok": true,
        "first_kept_message_index": int(indexes[cut_index]),
        "messages_to_summarize": messages_to_summarize,
        "turn_prefix_messages": turn_prefix_messages,
        "kept_messages": messages.slice(cut_index),
        "is_split_turn": is_split_turn,
        "tokens_before": estimate_provider_tokens(game_name),
        "previous_summary": str(state.previous_summary),
        "previous_details": state.previous_details
    }

func needs_recovery_marker(history: Array) -> bool:
    if history.is_empty():
        return false
    var last = history[-1]
    if typeof(last) != TYPE_DICTIONARY:
        return true
    if str(last.get("role", "")) != "assistant":
        return true
    if last.has("tool_calls") and not Array(last.get("tool_calls", [])).is_empty():
        return true
    return str(last.get("content", "")).strip_edges() == ""

func recovery_marker() -> Dictionary:
    return {
        "role": "assistant",
        "content": "The previous GameSmith turn ended before a final response. The workspace and Git may contain partial work; inspect the current files before acting on the new request."
    }

func import_legacy_transcript(game_name: String, entries: Array) -> Array:
    if exists(game_name):
        return read_for_provider(game_name)
    var imported: Array = []
    for entry in entries:
        if typeof(entry) != TYPE_DICTIONARY:
            continue
        var role = str(entry.get("role", ""))
        if role != "user" and role != "assistant":
            continue
        imported.append({"role": role, "content": str(entry.get("content", ""))})
    if imported.is_empty():
        return imported
    var path = metadata.conversation_path(game_name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return []
    for message in imported:
        file.store_line(JSON.stringify(message))
    file.close()
    return imported

func _estimate_message_tokens(message: Dictionary) -> int:
    var chars = 0
    var role = str(message.get("role", ""))
    if role == "assistant":
        var content = message.get("content", "")
        if typeof(content) == TYPE_STRING:
            chars += str(content).length()
        for key in ["reasoning_content", "reasoning"]:
            var reasoning = message.get(key, null)
            if typeof(reasoning) == TYPE_STRING:
                chars += str(reasoning).length()
        var calls = message.get("tool_calls", [])
        if typeof(calls) == TYPE_ARRAY:
            for call in calls:
                if typeof(call) != TYPE_DICTIONARY:
                    continue
                var fn = call.get("function", {})
                if typeof(fn) == TYPE_DICTIONARY:
                    chars += str(fn.get("name", "")).length()
                    chars += str(fn.get("arguments", "")).length()
    else:
        var content = message.get("content", "")
        if typeof(content) == TYPE_STRING:
            chars += str(content).length()
        else:
            chars += JSON.stringify(content).length()
    return ceili(float(chars) / 4.0)

func _is_verification_message(message: Dictionary) -> bool:
    return str(message.get("role", "")) == "system" and str(message.get("content", "")).begins_with(VERIFICATION_PREFIX)
