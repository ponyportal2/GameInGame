extends SceneTree

const Images = preload("res://src/core/image_generation.gd")

func _init() -> void:
    run.call_deferred()

func run() -> void:
    var backend = OS.get_environment("GAMESMITH_IMAGE_LIVE_BACKEND")
    if not backend in Images.BACKENDS:
        print("FAIL: explicitly select GAMESMITH_IMAGE_LIVE_BACKEND")
        quit(1)
        return
    if backend == "codex" and not OS.get_environment("GAMESMITH_CODEX_BIN").replace("\\", "/").ends_with("/tools/testing/codex-luna-launcher.mjs"):
        print("FAIL: live Codex image tests require the Luna launcher (gpt-6-luna/xhigh)")
        quit(1)
        return
    var workspace = "user://games/Native image acceptance"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    JsonStore.write_bytes_atomic(workspace.path_join("keep.txt"), "unchanged".to_utf8_buffer())
    MetadataStore.new().save_global_settings({"image_backend": backend})
    var service = Images.new()
    root.add_child(service)
    var args = {"prompt": "Generate a small simple blue circle icon on a white background. Use native image generation exactly once. No other tools.", "target_path": "assets/generated/native.png", "purpose": "native image integration acceptance"}
    var reference = OS.get_environment("GAMESMITH_IMAGE_LIVE_REFERENCE")
    if reference != "":
        var bytes = FileAccess.get_file_as_bytes(reference)
        JsonStore.write_bytes_atomic(workspace.path_join("reference.png"), bytes)
        args.reference_paths = ["reference.png"]
        args.prompt = "Use the reference image to generate one similar icon with a green circle instead of blue. Use your native image tool exactly once."
    var result = service.execute(workspace, args)
    if result.get("ok", false):
        for _i in 1250:
            result = service.execute(workspace, {"action": "status", "job_id": result.job_id})
            if result.get("state", "") != "running": break
            await create_timer(0.25).timeout
    print("NATIVE IMAGE RESULT: " + JSON.stringify(result))
    var valid = result.get("state", "") == "completed" and int(result.get("width", 0)) > 0 and FileAccess.file_exists(workspace.path_join(str(result.get("path", "")))) and FileAccess.get_file_as_string(workspace.path_join("keep.txt")) == "unchanged"
    print(("PASS: " if valid else "FAIL: ") + backend + " live image generation, publication and unchanged unrelated file")
    service.stop_all()
    service.queue_free()
    await process_frame
    quit(0 if valid else 1)
