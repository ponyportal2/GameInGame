extends SceneTree

const Images = preload("res://src/core/image_generation.gd")
var failures := 0

func _init() -> void:
    run.call_deferred()

func check(value: bool, message: String) -> void:
    print(("PASS: " if value else "FAIL: ") + message)
    if not value: failures += 1

func settle(service: Node, workspace: String, id: String) -> Dictionary:
    for _i in 600:
        var result = service.execute(workspace, {"action": "status", "job_id": id})
        if result.get("state", "") != "running": return result
        await create_timer(0.025).timeout
    return {"ok": false, "state": "timeout"}

func native_running(pid: int) -> bool:
    # Godot tracks its own child handles; the CLI is a grandchild of Godot.
    if pid <= 0: return false
    return OS.execute("node", ["-e", "try{process.kill(Number(process.argv[1]),0)}catch{process.exit(1)}", str(pid)], [], true) == 0

func run() -> void:
    var workspace = "user://games/Image fixture"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    JsonStore.write_bytes_atomic(workspace.path_join("keep.txt"), "unchanged".to_utf8_buffer())
    var fake = ProjectSettings.globalize_path("res://tools/testing/fake-image-native.mjs")
    for key in ["CODEX", "AGY", "GROK_BUILD", "CURSOR"]:
        OS.set_environment("GAMESMITH_" + key + "_BIN", fake)
    var runner = GameRunner.new()
    root.add_child(runner)
    var tools = GameTools.new(workspace, runner)
    var store = MetadataStore.new()
    store.save_global_settings({"image_backend": ""})
    check(not tools.execute("generate_image", {"prompt": "A circle"}).ok, "No implicit image vendor selection")
    var service = tools.image_supervisor
    for backend in Images.BACKENDS:
        store.save_global_settings({"image_backend": backend})
        var started = tools.execute("generate_image", {"prompt": "A circle", "target_path": "assets/" + backend + ".png"})
        check(started.ok and started.state == "running", backend + " starts a separate native image job")
        check(not service.execute("user://other", {"action": "status", "job_id": started.job_id}).ok, "Job cannot be inspected from another workspace")
        var result = await settle(service, workspace, str(started.job_id))
        check(result.get("state") == "completed" and result.get("width") == 1 and result.get("format") == "png", backend + " host decodes and publishes PNG metadata: " + JSON.stringify(result))
        check(FileAccess.file_exists(workspace.path_join("assets/" + backend + ".png")), "Requested game image exists")
        check(not DirAccess.dir_exists_absolute("user://host/images/".path_join(started.job_id)), backend + " completed job removes private runtime and image copies")
    service.probe_all()
    for _i in 600:
        if service.sessions.is_empty(): break
        await create_timer(0.025).timeout
    for backend in Images.BACKENDS:
        check(service.capabilities.get(backend, {}).get("available", false), backend + " capability probe completes without an image turn")
        check(not DirAccess.dir_exists_absolute("user://host/images/probe-" + backend), backend + " probe removes its private directory")
    OS.set_environment("GAMESMITH_IMAGE_FIXTURE", "wait")
    store.save_global_settings({"image_backend": "codex"})
    var waiting = service.execute(workspace, {"prompt": "Wait", "reference_paths": ["assets/codex.png"]})
    var native_pid_path = "user://host/images/".path_join(waiting.job_id).path_join("native-pid.txt")
    for _i in 400:
        if FileAccess.file_exists(native_pid_path): break
        await create_timer(0.025).timeout
    var native_pid = int(FileAccess.get_file_as_string(native_pid_path))
    check(FileAccess.file_exists(native_pid_path.get_base_dir().path_join("references/0.png")), "Running job contains a private reference copy")
    check(native_running(native_pid), "Native child is running before Stop")
    var stopped = service.execute(workspace, {"action": "stop", "job_id": waiting.job_id})
    check(stopped.state == "cancelled" and service.sessions.is_empty(), "Stop cancels and retires the existing process-tree session")
    check(native_pid > 0 and not native_running(native_pid), "Stop terminates the native child process")
    check(not DirAccess.dir_exists_absolute(native_pid_path.get_base_dir()), "Stop removes reference copies only after native child shutdown")
    check(not FileAccess.file_exists(workspace.path_join("assets/generated/image.png")), "Cancelled image is never published")
    OS.unset_environment("GAMESMITH_IMAGE_FIXTURE")
    OS.set_environment("GAMESMITH_IMAGE_FIXTURE", "fail")
    var failed_job = service.execute(workspace, {"prompt": "An icon"})
    var failed_result = await settle(service, workspace, str(failed_job.job_id))
    check(failed_result.get("state") == "failed" and not service.capabilities.codex.available and "Fixture image limit" in str(service.capabilities.codex.reason), "Native failure updates checked capability with the actual reason")
    check(not DirAccess.dir_exists_absolute("user://host/images/".path_join(failed_job.job_id)), "Failed native job removes its private directory")
    check(FileAccess.file_exists("user://host/images/backend-results.json"), "Cleanup retains small backend result metadata")
    OS.unset_environment("GAMESMITH_IMAGE_FIXTURE")
    var recovered_job = service.execute(workspace, {"prompt": "An icon", "target_path": "assets/recovered.png"})
    var recovered_result = await settle(service, workspace, str(recovered_job.job_id))
    check(recovered_result.get("state") == "completed" and service.capabilities.codex.available, "Successful explicit retry clears stale backend failure")
    for mode in ["corrupt", "opaque"]:
        OS.set_environment("GAMESMITH_IMAGE_FIXTURE", mode)
        var started = service.execute(workspace, {"prompt": "An icon", "target_path": "assets/" + mode + ".png", "transparent": mode == "opaque"})
        var result = await settle(service, workspace, str(started.job_id))
        check(result.get("state") == "failed", "Host rejects " + mode + " image results: " + JSON.stringify(result))
        check(not FileAccess.file_exists(workspace.path_join("assets/" + mode + ".png")), "Rejected image is never published")
        check(not DirAccess.dir_exists_absolute("user://host/images/".path_join(started.job_id)), "Rejected " + mode + " output removes private image copies")
    OS.unset_environment("GAMESMITH_IMAGE_FIXTURE")
    check(service.capabilities.codex.available, "Invalid image output does not invent an authentication or entitlement failure")
    var cleanup_directory = ProjectSettings.globalize_path("user://host/images/cleanup-link")
    DirAccess.make_dir_recursive_absolute(cleanup_directory)
    var linked = OS.execute("node", ["-e", "require('node:fs').symlinkSync(process.argv[1],process.argv[2],process.platform==='win32'?'junction':'dir')", ProjectSettings.globalize_path(workspace), cleanup_directory.path_join("game-link")], [], true)
    check(linked == 0, "Cleanup fixture creates a link to unrelated game data")
    service._retire("cleanup-link")
    check(not DirAccess.dir_exists_absolute(cleanup_directory), "Private cleanup unlinks directory links without following them")
    check(FileAccess.get_file_as_string(workspace.path_join("keep.txt")) == "unchanged", "Unrelated game file remains unchanged")
    service.stop_all()
    runner.queue_free()
    await process_frame
    quit(1 if failures else 0)
