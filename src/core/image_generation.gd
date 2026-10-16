extends Node

signal capability_changed(harness: String, result: Dictionary)

const Inventory = preload("res://src/agent/harness_inventory.gd")
const Session = preload("res://src/agent/command_code_session.gd")
const BACKENDS = ["agy", "codex", "grok-build", "cursor"]
var jobs: Dictionary = {}
var sessions: Dictionary = {}
var capabilities: Dictionary = {}

func execute(workspace: String, args: Dictionary) -> Dictionary:
    var action = str(args.get("action", "start"))
    var id = str(args.get("job_id", ""))
    if action == "capabilities":
        if capabilities.is_empty(): probe_all()
        return {"ok": true, "selected_backend": str(MetadataStore.new().global_settings().get("image_backend", "")), "backends": capabilities.duplicate(true)}
    if action == "status" or action == "stop":
        if not jobs.has(id) or str(jobs[id].workspace) != workspace:
            return {"ok": false, "error": "Unknown image job for this workspace."}
        if action == "stop" and jobs[id].state == "running":
            jobs[id].state = "cancelled"
            _retire(id)
        return _public(id)
    if action != "start": return {"ok": false, "error": "Unknown image operation."}
    var backend = str(MetadataStore.new().global_settings().get("image_backend", ""))
    if not backend in BACKENDS:
        return {"ok": false, "error": "Select an image backend in Settings > Images. No backend is selected."}
    for existing in jobs.values():
        if existing.state == "running": return {"ok": false, "error": "An image job is already running. Poll or stop it first."}
    id = str(Time.get_unix_time_from_system()).replace(".", "-") + "-" + str(randi())
    var config = {"harness": backend, "workspace": ProjectSettings.globalize_path(workspace), "prompt": args.get("prompt", ""), "purpose": args.get("purpose", "game asset"), "target_path": args.get("target_path", "assets/generated/image.png"), "reference_paths": args.get("reference_paths", []), "transparent": args.get("transparent", false)}
    jobs[id] = {"job_id": id, "harness": backend, "workspace": workspace, "state": "running", "path": config.target_path}
    var started = _launch(id, config)
    if not started.ok: _fail(id, str(started.error))
    # Retain only bounded metadata; native conversations and logs stay outside the game.
    if jobs.size() > 32:
        for old in jobs.keys():
            if old != id and jobs[old].state != "running":
                jobs.erase(old)
                break
    return _public(id)

func _launch(id: String, config: Dictionary) -> Dictionary:
    var directory = ProjectSettings.globalize_path("user://host/images/".path_join(id))
    var assembled = Inventory.assemble_runtime(str(config.harness), directory)
    if not assembled.ok: return assembled
    config.directory = directory
    config.worker = directory.path_join("image-worker.mjs")
    config.config_path = directory.path_join("job.json")
    config.label = "Image generation"
    if not JsonStore.write_dict(config.config_path, config): return {"ok": false, "error": "Could not save image job configuration."}
    var session = Session.new()
    add_child(session)
    sessions[id] = session
    session.record_received.connect(func(record): _record(id, config, record))
    session.process_stopped.connect(func(message):
        if jobs.has(id) and jobs[id].state == "running": _fail(id, message)
        elif bool(config.get("probe", false)) and bool(capabilities.get(str(config.harness), {}).get("checking", false)):
            _capability(id, str(config.harness), {"available": false, "reason": message})
    )
    var result = session.start(config)
    if not result.ok: _retire(id)
    return result

func probe_all() -> void:
    for harness in BACKENDS:
        var id = "probe-" + harness
        if sessions.has(id): continue
        capabilities[harness] = {"available": false, "reason": "Checking installed CLI and sign-in…", "checking": true}
        var result = _launch(id, {"harness": harness, "probe": true})
        if not result.ok: _capability(id, harness, {"available": false, "reason": str(result.error)})

func _capability(id: String, harness: String, result: Dictionary) -> void:
    var previous = JsonStore.read_dict("user://host/images/backend-results.json").get(harness, {})
    if result.get("available", false) and previous.get("state", "") == "failed":
        result.available = false
        result.reason = str(result.reason) + " Last image attempt failed: " + str(previous.get("error", "Unknown native error")) + " Retry generation after resolving this."
    capabilities[harness] = result
    capability_changed.emit(harness, result.duplicate(true))
    _retire(id)

func _record(id: String, config: Dictionary, record: Dictionary) -> void:
    if record.get("type") == "image_capability":
        _capability(id, str(config.harness), {"available": bool(record.get("available", false)), "reason": str(record.get("reason", ""))})
        return
    if record.get("type") == "image_error":
        if bool(config.get("probe", false)):
            _capability(id, str(config.harness), {"available": false, "reason": str(record.error)})
        else: _fail(id, str(record.error), record.get("phase", "") == "native")
        return
    if record.get("type") != "image_ready" or not jobs.has(id) or jobs[id].state != "running": return
    var bytes = FileAccess.get_file_as_bytes(str(config.directory).path_join("result.raw"))
    var image = Image.new()
    var error = ERR_FILE_UNRECOGNIZED
    match str(record.get("format", "")):
        "png": error = image.load_png_from_buffer(bytes)
        "jpeg": error = image.load_jpg_from_buffer(bytes)
        "webp": error = image.load_webp_from_buffer(bytes)
    if error != OK or image.is_empty() or image.get_width() > 16384 or image.get_height() > 16384 or image.get_width() * image.get_height() > 67108864:
        _fail(id, "Native result could not be decoded as a supported image within size limits.")
        return
    if bool(config.get("transparent", false)) and not image.is_invisible() and not image.detect_alpha():
        _fail(id, "The selected backend returned an opaque image although transparency was requested.")
        return
    if image.save_png(str(config.directory).path_join("result.png")) != OK:
        _fail(id, "Could not save the validated image.")
        return
    var published: Dictionary = await sessions[id].command({"type": "publish"})
    if not jobs.has(id) or jobs[id].state != "running": return
    if not published.get("success", false):
        _fail(id, str(published.get("error", "Could not publish the generated image.")))
        return
    jobs[id].merge({"state": "completed", "path": published.path, "width": image.get_width(), "height": image.get_height(), "format": "png"}, true)
    _remember_result(id)
    _retire(id)

func _fail(id: String, message: String, native_failure: bool = false) -> void:
    if not jobs.has(id) or jobs[id].state != "running": return
    jobs[id].state = "failed"
    jobs[id].error = message
    if native_failure: _remember_result(id)
    _retire(id)

func _public(id: String) -> Dictionary:
    var result: Dictionary = jobs[id].duplicate(true)
    result.erase("workspace")
    result.ok = result.state != "failed"
    return result

func _remember_result(id: String) -> void:
    var path = "user://host/images/backend-results.json"
    var results = JsonStore.read_dict(path)
    results[str(jobs[id].harness)] = {"state": jobs[id].state, "error": jobs[id].get("error", "")}
    JsonStore.write_dict(path, results)
    var harness = str(jobs[id].harness)
    if capabilities.has(harness):
        var result = {"available": jobs[id].state == "completed", "reason": "Last image generation completed successfully." if jobs[id].state == "completed" else "Last image attempt failed: " + str(jobs[id].get("error", "")) + " Resolve this and retry the selected backend."}
        capabilities[harness] = result
        capability_changed.emit(harness, result.duplicate(true))

func _retire(id: String) -> void:
    if sessions.has(id):
        var session = sessions[id]
        sessions.erase(id)
        session.retire()

func stop_all() -> void:
    for id in sessions.keys():
        if jobs.has(id) and jobs[id].state == "running": jobs[id].state = "cancelled"
        _retire(id)

func has_running() -> bool:
    for job in jobs.values():
        if job.state == "running": return true
    return false

func _exit_tree() -> void:
    stop_all()
