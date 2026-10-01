class_name CompactionService
extends RefCounted

const ConversationStoreScript = preload("res://src/core/conversation_store.gd")

const TOOL_RESULT_MAX_CHARS = 2000

const SUMMARIZATION_SYSTEM_PROMPT = "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\n\nDo NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary."

const SUMMARIZATION_PROMPT = """The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.

Use this EXACT format:

## Goal
[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned by user]
- [Or "(none)" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Current work]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Any data, examples, or references needed to continue]
- [Or "(none)" if not applicable]

Keep each section concise. Preserve exact file paths, function names, and error messages."""

const UPDATE_SUMMARIZATION_INSTRUCTIONS = """Update the existing structured summary with new information. RULES:
- PRESERVE all existing information from the previous summary
- ADD new progress, decisions, and context from the new messages
- UPDATE the Progress section: move items from "In Progress" to "Done" when completed
- UPDATE "Next Steps" based on what was accomplished
- PRESERVE exact file paths, function names, and error messages
- If something is no longer relevant, you may remove it

Use this EXACT format:

## Goal
[Preserve existing goals, add new ones if the task expanded]

## Constraints & Preferences
- [Preserve existing, add new ones discovered]

## Progress
### Done
- [x] [Include previously done items AND newly completed items]

### In Progress
- [ ] [Current work - update based on progress]

### Blocked
- [Current blockers - remove if resolved]

## Key Decisions
- **[Decision]**: [Brief rationale] (preserve all previous, add new)

## Next Steps
1. [Update based on current state]

## Critical Context
- [Preserve important context, add new if needed]

Keep each section concise. Preserve exact file paths, function names, and error messages."""

const UPDATE_SUMMARIZATION_PROMPT = "The messages above are NEW conversation messages to incorporate into the existing summary provided in <previous-summary> tags.\n\n" + UPDATE_SUMMARIZATION_INSTRUCTIONS

const TURN_PREFIX_SUMMARIZATION_PROMPT = """The messages above are earlier context from an ongoing conversation. Later messages are stored separately and do not need to be reconstructed.

Create a concise checkpoint of the user's request and the progress shown above. This checkpoint will be placed before the later messages so the conversation can continue with the necessary context.

## Original Request
[What did the user ask for?]

## Progress So Far
- [Key decisions and work completed in these messages]

## Context Needed to Continue
- [Information from these messages needed to understand the later work]

Only summarize information explicitly present above. Do not infer or recreate later messages."""

var conversation = ConversationStoreScript.new()

func compact_game(game_name: String, provider: Variant, keep_recent_tokens: int, before_call: Callable = Callable(), after_call: Callable = Callable()) -> Dictionary:
    var preparation = conversation.prepare_compaction(game_name, keep_recent_tokens)
    if not bool(preparation.get("ok", false)):
        return preparation

    var previous_summary = str(preparation.get("previous_summary", ""))
    var messages_to_summarize: Array = preparation.get("messages_to_summarize", [])
    var turn_prefix_messages: Array = preparation.get("turn_prefix_messages", [])
    var summary = ""
    if bool(preparation.get("is_split_turn", false)) and not turn_prefix_messages.is_empty():
        var history_text = previous_summary if previous_summary != "" else "No prior history."
        if not messages_to_summarize.is_empty():
            var history_result = await _generate_history_summary(provider, messages_to_summarize, previous_summary, before_call, after_call)
            if not bool(history_result.get("ok", false)):
                return history_result
            history_text = str(history_result.summary)
        var prefix_result = await _generate_turn_prefix_summary(provider, turn_prefix_messages, before_call, after_call)
        if not bool(prefix_result.get("ok", false)):
            return prefix_result
        summary = history_text + "\n\n---\n\n**Turn Context (split turn):**\n\n" + str(prefix_result.summary)
    else:
        var result = await _generate_history_summary(provider, messages_to_summarize, previous_summary, before_call, after_call)
        if not bool(result.get("ok", false)):
            return result
        summary = str(result.summary)

    var details = _collect_file_operations(
        messages_to_summarize,
        turn_prefix_messages,
        preparation.get("previous_details", {})
    )
    summary += _format_file_operations(details)
    var persisted = conversation.append_compaction(
        game_name,
        summary,
        int(preparation.first_kept_message_index),
        int(preparation.tokens_before),
        details
    )
    if not persisted:
        return {"ok": false, "error": "Could not persist compaction checkpoint."}
    return {
        "ok": true,
        "summary": summary,
        "tokens_before": int(preparation.tokens_before),
        "tokens_after": conversation.estimate_provider_tokens(game_name),
        "first_kept_message_index": int(preparation.first_kept_message_index),
        "details": details
    }

func _generate_history_summary(provider: Variant, messages: Array, previous_summary: String, before_call: Callable, after_call: Callable) -> Dictionary:
    if messages.is_empty() and previous_summary != "":
        return {"ok": true, "summary": previous_summary}
    var base_prompt = UPDATE_SUMMARIZATION_PROMPT if previous_summary != "" else SUMMARIZATION_PROMPT
    var prompt = "<conversation>\n%s\n</conversation>\n\n" % _serialize_conversation(messages)
    if previous_summary != "":
        prompt += "<previous-summary>\n%s\n</previous-summary>\n\n" % previous_summary
    prompt += base_prompt
    return await _summary_call(provider, prompt, before_call, after_call)

func _generate_turn_prefix_summary(provider: Variant, messages: Array, before_call: Callable, after_call: Callable) -> Dictionary:
    var prompt = "# Conversation\n%s\n\n# Instructions\n%s" % [_serialize_conversation(messages), TURN_PREFIX_SUMMARIZATION_PROMPT]
    return await _summary_call(provider, prompt, before_call, after_call)

func _summary_call(provider: Variant, prompt: String, before_call: Callable, after_call: Callable) -> Dictionary:
    if before_call.is_valid():
        await before_call.call()
    var result: Dictionary = await provider.complete([
        {"role": "system", "content": SUMMARIZATION_SYSTEM_PROMPT},
        {"role": "user", "content": prompt}
    ], [])
    if after_call.is_valid():
        after_call.call()
    if not bool(result.get("ok", false)):
        return {"ok": false, "error": "Compaction summarization failed: " + str(result.get("error", "Unknown provider error."))}
    var message = result.get("message", {})
    if typeof(message) != TYPE_DICTIONARY:
        return {"ok": false, "error": "Compaction summarization returned an invalid assistant message."}
    var calls = message.get("tool_calls", [])
    if typeof(calls) == TYPE_ARRAY and not calls.is_empty():
        return {"ok": false, "error": "Compaction summarization attempted to call a tool."}
    var text = str(message.get("content", "")).strip_edges()
    if text == "":
        return {"ok": false, "error": "Compaction summarization returned an empty summary."}
    return {"ok": true, "summary": text}

func _serialize_conversation(messages: Array) -> String:
    var parts: Array[String] = []
    for message in messages:
        if typeof(message) != TYPE_DICTIONARY:
            continue
        var role = str(message.get("role", ""))
        if role == "user":
            var content = str(message.get("content", ""))
            if content != "":
                parts.append("[User]: " + content)
        elif role == "assistant":
            for key in ["reasoning_content", "reasoning"]:
                var reasoning = message.get(key, null)
                if typeof(reasoning) == TYPE_STRING and str(reasoning) != "":
                    parts.append("[Assistant thinking]: " + str(reasoning))
                    break
            var content = message.get("content", "")
            if typeof(content) == TYPE_STRING and str(content) != "":
                parts.append("[Assistant]: " + str(content))
            var tool_calls = message.get("tool_calls", [])
            if typeof(tool_calls) == TYPE_ARRAY and not tool_calls.is_empty():
                var calls: Array[String] = []
                for call in tool_calls:
                    if typeof(call) != TYPE_DICTIONARY:
                        continue
                    var fn = call.get("function", {})
                    if typeof(fn) != TYPE_DICTIONARY:
                        continue
                    var args_text = str(fn.get("arguments", "{}"))
                    var parsed = JSON.parse_string(args_text)
                    var rendered_args = args_text
                    if typeof(parsed) == TYPE_DICTIONARY:
                        var fields: Array[String] = []
                        for key in parsed:
                            fields.append("%s=%s" % [str(key), JSON.stringify(parsed[key])])
                        rendered_args = ", ".join(fields)
                    calls.append("%s(%s)" % [str(fn.get("name", "")), rendered_args])
                if not calls.is_empty():
                    parts.append("[Assistant tool calls]: " + "; ".join(calls))
        elif role == "tool":
            var content = str(message.get("content", ""))
            if content != "":
                parts.append("[Tool result]: " + _truncate_tool_result(content))
    return "\n\n".join(parts)

func _truncate_tool_result(text: String) -> String:
    if text.length() <= TOOL_RESULT_MAX_CHARS:
        return text
    return text.left(TOOL_RESULT_MAX_CHARS) + "\n\n[... %d more characters truncated]" % (text.length() - TOOL_RESULT_MAX_CHARS)

func _collect_file_operations(history: Array, turn_prefix: Array, previous_details: Variant) -> Dictionary:
    var read_files: Dictionary = {}
    var modified_files: Dictionary = {}
    if typeof(previous_details) == TYPE_DICTIONARY:
        for path in previous_details.get("readFiles", []):
            read_files[str(path)] = true
        for path in previous_details.get("modifiedFiles", []):
            modified_files[str(path)] = true
    var combined: Array = []
    combined.append_array(history)
    combined.append_array(turn_prefix)
    for message in combined:
        if typeof(message) != TYPE_DICTIONARY or str(message.get("role", "")) != "assistant":
            continue
        var calls = message.get("tool_calls", [])
        if typeof(calls) != TYPE_ARRAY:
            continue
        for call in calls:
            if typeof(call) != TYPE_DICTIONARY:
                continue
            var fn = call.get("function", {})
            if typeof(fn) != TYPE_DICTIONARY:
                continue
            var name = str(fn.get("name", ""))
            var args = JSON.parse_string(str(fn.get("arguments", "{}")))
            if typeof(args) != TYPE_DICTIONARY:
                continue
            if name == "read_file":
                var path = str(args.get("path", ""))
                if path != "": read_files[path] = true
            elif name in ["write_file", "patch_file", "delete_path"]:
                var path = str(args.get("path", ""))
                if path != "": modified_files[path] = true
            elif name == "move_path":
                var from_path = str(args.get("from", ""))
                var to_path = str(args.get("to", ""))
                if from_path != "": modified_files[from_path] = true
                if to_path != "": modified_files[to_path] = true
    for path in modified_files:
        read_files.erase(path)
    var reads: Array = read_files.keys()
    var modified: Array = modified_files.keys()
    reads.sort()
    modified.sort()
    return {"readFiles": reads, "modifiedFiles": modified}

func _format_file_operations(details: Dictionary) -> String:
    var sections: Array[String] = []
    var reads: Array = details.get("readFiles", [])
    var modified: Array = details.get("modifiedFiles", [])
    if not reads.is_empty():
        sections.append("<read-files>\n%s\n</read-files>" % "\n".join(PackedStringArray(reads)))
    if not modified.is_empty():
        sections.append("<modified-files>\n%s\n</modified-files>" % "\n".join(PackedStringArray(modified)))
    if sections.is_empty():
        return ""
    return "\n\n" + "\n\n".join(sections)
