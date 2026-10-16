extends RefCounted

const Store = preload("res://src/core/json_store.gd")

static func all() -> Array:
    var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/agent/harnesses.json"))
    return data.get("harnesses", []) if data is Dictionary else []

static func get_harness(id: String) -> Dictionary:
    for item in all():
        if item.id == id: return item
    return {}

static func supports_reset(id: String) -> bool:
    return bool(get_harness(id).get("reset", false))

# The one materialization path: production controllers, source fixtures and PCK
# verification invoke this same function against the same packaged module map.
static func assemble_runtime(id: String, destination: String) -> Dictionary:
    var entry = get_harness(id)
    if entry.is_empty(): return {"ok": false, "error": "Unknown harness: " + id}
    for pair in entry.modules:
        var source = "res://tools/" + str(pair[1])
        var target = destination.path_join(str(pair[0]))
        if not FileAccess.file_exists(source):
            return {"ok": false, "error": "Missing " + id + " module: " + str(pair[0])}
        var contents = FileAccess.get_file_as_bytes(source)
        # Runtime retirement should not rewrite identical policy modules.
        if FileAccess.file_exists(target) and FileAccess.get_file_as_bytes(target) == contents:
            continue
        if not Store.write_bytes_atomic(target, contents):
            return {"ok": false, "error": "Could not assemble " + id + " module: " + str(pair[0])}
    return {"ok": true}
