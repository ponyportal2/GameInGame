extends RefCounted

# Started before loading generated code. This thread survives a hung _ready(),
# property getter, game action, or cleanup callback. It kills only its own PID.
var thread := Thread.new()
var mutex := Mutex.new()
var stopping := false
var config: Dictionary

func start(settings: Dictionary) -> void:
    config = settings.duplicate(true)
    thread.start(_watch)

func close() -> void:
    mutex.lock()
    stopping = true
    mutex.unlock()
    if thread.is_started():
        thread.wait_to_finish()

func _watch() -> void:
    var last_heartbeat = Time.get_ticks_msec()
    var previous = ""
    var shutdown_reason = ""
    var shutdown_deadline := 0
    while true:
        OS.delay_msec(200)
        mutex.lock()
        var done = stopping
        mutex.unlock()
        if done:
            return
        var heartbeat = FileAccess.get_file_as_string(config.control_dir.path_join("parent-heartbeat"))
        if heartbeat.begins_with(str(config.parent_token) + ":") and heartbeat != previous:
            previous = heartbeat
            last_heartbeat = Time.get_ticks_msec()
        var reason = ""
        if Time.get_ticks_msec() - last_heartbeat > int(config.get("parent_grace_ms", 15000)):
            reason = "parent_lost"
        elif preload("res://src/core/test_evidence.gd").size_bytes(config.control_dir) > int(config.get("run_budget_bytes", 32 * 1024 * 1024)):
            reason = "test_storage_budget"
        if reason != "" and shutdown_reason == "":
            shutdown_reason = reason
            shutdown_deadline = Time.get_ticks_msec() + 5000
            # Try the cooperative path first, but this thread owns escalation.
            JsonStore.write_dict(config.control_dir.path_join("watchdog.json"), {"reason": reason, "method": "requested", "utc": Time.get_datetime_string_from_system(true) + "Z"})
            JsonStore.write_dict(config.control_dir.path_join("stop.json"), {"stop": true})
        if shutdown_deadline > 0 and Time.get_ticks_msec() >= shutdown_deadline:
            # Separate file: never race the child's status/outcome writer.
            JsonStore.write_dict(config.control_dir.path_join("watchdog.json"), {"reason": shutdown_reason, "method": "forced", "utc": Time.get_datetime_string_from_system(true) + "Z"})
            OS.kill(OS.get_process_id())
            return
