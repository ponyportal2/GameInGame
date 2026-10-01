class_name OpenAICompatibleProvider
extends RefCounted

const DEFAULT_TIMEOUT_SEC := 300.0

var owner: Node
var endpoint = ""
var api_key = ""
var model = ""
var extra_headers: PackedStringArray = []
var reasoning_effort = ""
var api_key_required = true
var request_timeout_sec := DEFAULT_TIMEOUT_SEC

func _init(p_owner: Node, p_endpoint: String, p_key: String, p_model: String, p_headers: PackedStringArray = [], p_reasoning_effort: String = "", p_api_key_required: bool = true):
    owner = p_owner
    endpoint = p_endpoint
    api_key = p_key
    model = p_model
    extra_headers = p_headers
    reasoning_effort = p_reasoning_effort
    api_key_required = p_api_key_required

func build_payload(messages: Array, tools: Array) -> Dictionary:
    var body = {
        "model": model,
        "messages": messages,
        "temperature": 0.2
    }
    if not tools.is_empty():
        body["tools"] = tools
        body["tool_choice"] = "auto"
    var effort = reasoning_effort.strip_edges()
    if effort != "":
        body["reasoning_effort"] = effort
        if effort != "none":
            body.erase("temperature")
    return body

func diagnostic_summary(messages: Array = [], tools: Array = []) -> String:
    var context_chars := 0
    for message in messages:
        context_chars += JSON.stringify(message).length()
    return "endpoint=%s model=%s timeout_sec=%.1f messages=%d context_chars=%d tools=%d" % [
        _safe_endpoint(), model, request_timeout_sec, messages.size(), context_chars, tools.size()
    ]

func complete(messages: Array, tools: Array) -> Dictionary:
    if api_key_required and api_key.strip_edges() == "":
        return {"ok": false, "error": "No API key configured for this provider."}
    if model.strip_edges() == "":
        return {"ok": false, "error": "No model configured for this provider."}
    if endpoint.strip_edges() == "":
        return {"ok": false, "error": "No API endpoint configured for this provider."}

    var request = HTTPRequest.new()
    request.timeout = request_timeout_sec
    owner.add_child(request)
    var headers = PackedStringArray(["Content-Type: application/json"])
    if api_key.strip_edges() != "":
        headers.append("Authorization: Bearer " + api_key)
    for h in extra_headers:
        headers.append(h)
    var body = JSON.stringify(build_payload(messages, tools))
    var started_ms := Time.get_ticks_msec()
    var start_err = request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
    if start_err != OK:
        request.queue_free()
        return {
            "ok": false,
            "error": "HTTP request could not start (%d)." % start_err,
            "diagnostics": {
                "transport": "start_error",
                "start_error": start_err,
                "http_status": 0,
                "elapsed_ms": Time.get_ticks_msec() - started_ms,
                "endpoint": _safe_endpoint(),
                "request_bytes": body.to_utf8_buffer().size(),
                "messages": messages.size(),
                "tools": tools.size()
            }
        }

    var completed = await request.request_completed
    request.queue_free()
    var elapsed_ms := Time.get_ticks_msec() - started_ms
    var transport_result: int = int(completed[0])
    var status: int = int(completed[1])
    var response_headers: PackedStringArray = completed[2]
    var raw: PackedByteArray = completed[3]
    var text = raw.get_string_from_utf8()
    var diagnostics = {
        "transport": _transport_result_name(transport_result),
        "transport_result": transport_result,
        "http_status": status,
        "elapsed_ms": elapsed_ms,
        "timeout_sec": request_timeout_sec,
        "endpoint": _safe_endpoint(),
        "request_bytes": body.to_utf8_buffer().size(),
        "response_bytes": raw.size(),
        "messages": messages.size(),
        "tools": tools.size(),
        "response_headers": _safe_response_headers(response_headers)
    }

    if transport_result != HTTPRequest.RESULT_SUCCESS:
        if transport_result == HTTPRequest.RESULT_TIMEOUT:
            return {
                "ok": false,
                "error": "Provider request timed out after %.1fs before an HTTP response." % request_timeout_sec,
                "diagnostics": diagnostics
            }
        return {
            "ok": false,
            "error": "Provider transport failed (%s, result=%d, HTTP=%d) after %.1fs." % [
                _transport_result_name(transport_result), transport_result, status, float(elapsed_ms) / 1000.0
            ],
            "diagnostics": diagnostics
        }

    var json = JSON.new()
    var parsed: Variant = null
    if json.parse(text) == OK:
        parsed = json.data
    if status < 200 or status >= 300:
        var detail = text.left(1200)
        if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
            detail = JSON.stringify(parsed.error)
        diagnostics["response_excerpt"] = detail.left(1200)
        return {"ok": false, "error": "Provider HTTP %d: %s" % [status, detail], "diagnostics": diagnostics}
    if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices") or parsed.choices.is_empty():
        diagnostics["response_excerpt"] = text.left(1200)
        return {"ok": false, "error": "Provider returned an unexpected response.", "diagnostics": diagnostics}

    var choice = parsed.choices[0]
    if typeof(choice) == TYPE_DICTIONARY:
        diagnostics["finish_reason"] = str(choice.get("finish_reason", ""))
    if typeof(parsed.get("usage", null)) == TYPE_DICTIONARY:
        var usage: Dictionary = parsed.usage
        diagnostics["prompt_tokens"] = int(usage.get("prompt_tokens", 0))
        diagnostics["completion_tokens"] = int(usage.get("completion_tokens", 0))
        diagnostics["total_tokens"] = int(usage.get("total_tokens", 0))
    return {"ok": true, "message": choice.message, "diagnostics": diagnostics}

func _transport_result_name(result: int) -> String:
    match result:
        HTTPRequest.RESULT_SUCCESS: return "success"
        HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: return "chunked_body_size_mismatch"
        HTTPRequest.RESULT_CANT_CONNECT: return "cant_connect"
        HTTPRequest.RESULT_CANT_RESOLVE: return "cant_resolve"
        HTTPRequest.RESULT_CONNECTION_ERROR: return "connection_error"
        HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "tls_handshake_error"
        HTTPRequest.RESULT_NO_RESPONSE: return "no_response"
        HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "body_size_limit_exceeded"
        HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: return "body_decompress_failed"
        HTTPRequest.RESULT_REQUEST_FAILED: return "request_failed"
        HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: return "download_file_cant_open"
        HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: return "download_file_write_error"
        HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "redirect_limit_reached"
        HTTPRequest.RESULT_TIMEOUT: return "timeout"
        _: return "unknown"

func _safe_endpoint() -> String:
    var safe = endpoint.strip_edges()
    var query = safe.find("?")
    if query >= 0:
        safe = safe.left(query)
    var fragment = safe.find("#")
    if fragment >= 0:
        safe = safe.left(fragment)
    var scheme = safe.find("://")
    if scheme >= 0:
        var authority_start = scheme + 3
        var slash = safe.find("/", authority_start)
        var authority_end = slash if slash >= 0 else safe.length()
        var authority = safe.substr(authority_start, authority_end - authority_start)
        var at = authority.rfind("@")
        if at >= 0:
            safe = safe.substr(0, authority_start) + authority.substr(at + 1) + safe.substr(authority_end)
    return safe

func _safe_response_headers(headers: PackedStringArray) -> Array:
    var out: Array = []
    for header in headers:
        var lower = header.to_lower()
        for allowed in ["x-request-id:", "request-id:", "cf-ray:", "server:", "retry-after:"]:
            if lower.begins_with(allowed):
                out.append(header.left(500))
                break
    return out
