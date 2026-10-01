class_name OpenAICompatibleProvider
extends RefCounted

var owner: Node
var endpoint = ""
var api_key = ""
var model = ""
var extra_headers: PackedStringArray = []
var reasoning_effort = ""
var api_key_required = true

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
        "tools": tools,
        "tool_choice": "auto",
        "temperature": 0.2
    }
    var effort = reasoning_effort.strip_edges()
    if effort != "":
        body["reasoning_effort"] = effort
        # Reasoning-capable OpenAI-style APIs commonly reject sampling controls
        # when reasoning is enabled. "none" retains ordinary sampling behavior.
        if effort != "none":
            body.erase("temperature")
    return body

func complete(messages: Array, tools: Array) -> Dictionary:
    if api_key_required and api_key.strip_edges() == "":
        return {"ok": false, "error": "No API key configured for this provider."}
    if model.strip_edges() == "":
        return {"ok": false, "error": "No model configured for this provider."}
    if endpoint.strip_edges() == "":
        return {"ok": false, "error": "No API endpoint configured for this provider."}
    var request = HTTPRequest.new()
    request.timeout = 90.0
    owner.add_child(request)
    var headers = PackedStringArray(["Content-Type: application/json"])
    if api_key.strip_edges() != "":
        headers.append("Authorization: Bearer " + api_key)
    for h in extra_headers:
        headers.append(h)
    var body = JSON.stringify(build_payload(messages, tools))
    var start_err = request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
    if start_err != OK:
        request.queue_free()
        return {"ok": false, "error": "HTTP request could not start (%d)." % start_err}
    var completed = await request.request_completed
    request.queue_free()
    var status: int = completed[1]
    var raw: PackedByteArray = completed[3]
    var text = raw.get_string_from_utf8()
    var json = JSON.new()
    var parsed: Variant = null
    if json.parse(text) == OK:
        parsed = json.data
    if status < 200 or status >= 300:
        var detail = text.left(1200)
        if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
            detail = JSON.stringify(parsed.error)
        return {"ok": false, "error": "Provider HTTP %d: %s" % [status, detail]}
    if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices") or parsed.choices.is_empty():
        return {"ok": false, "error": "Provider returned an unexpected response."}
    return {"ok": true, "message": parsed.choices[0].message}
