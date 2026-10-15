extends SceneTree

var failures := 0
var passed := 0
var tools

func _init() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    if condition:
        passed += 1
        print("PASS: ", message)
    else:
        failures += 1
        push_error("FAIL: " + message)

func wait_job(id: String, seconds := 20.0) -> Dictionary:
    var deadline = Time.get_ticks_msec() + int(seconds * 1000)
    while Time.get_ticks_msec() < deadline:
        var result: Dictionary = tools.execute("blender", {"action": "status", "run_id": id})
        if result.get("state") in ["completed", "failed", "cancelled"]: return result
        await create_timer(0.05).timeout
    return {"ok": false, "error": "Acceptance timed out", "state": "timeout"}

func run() -> void:
    var workspace = "user://games/Blender acceptance"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    var runner = GameRunner.new()
    root.add_child(runner)
    tools = GameTools.new(workspace, runner)
    var guide: Dictionary = tools.execute("blender", {"action": "guide"})
    check(guide.ok and "GLTFDocument" in guide.instructions, "shared Blender guide explains runtime assets")
    var previous = OS.get_environment("GAMESMITH_BLENDER_BIN")
    OS.set_environment("GAMESMITH_BLENDER_BIN", "C:/missing-gamesmith-blender.exe")
    tools.write_file("build.py", "import bpy\n")
    var job: Dictionary = tools.execute("blender", {"action": "start", "script": "build.py"})
    check(job.ok and job.state == "starting", "job launch returns immediately")
    var result: Dictionary = await wait_job(job.run_id)
    check(result.get("state") == "failed" and "Blender" in result.get("error", ""), "missing executable returns actionable tool failure")
    if previous == "": OS.unset_environment("GAMESMITH_BLENDER_BIN")
    else: OS.set_environment("GAMESMITH_BLENDER_BIN", previous)
    # Decode a real PNG, including compressed bytes, through the shipped runtime.
    var image = Image.create(16, 16, false, Image.FORMAT_RGB8)
    image.fill(Color.RED)
    image.save_png(ProjectSettings.globalize_path(workspace.path_join("preview.png")))
    result = tools.execute("blender", {"action": "inspect", "path": "preview.png"})
    check(result.get("ok", false) and result.get("width") == 16 and result.has("image_base64"), "PNG inspection delivers image bytes and dimensions")
    result = tools.execute("blender", {"action": "inspect", "path": "../outside.png"})
    check(not result.ok, "preview cannot escape workspace")
    check(not tools.execute("blender", {"action": "status", "run_id": "../unknown"}).ok, "unknown job references fail closed")
    # Every controller inherits the same thin Blender instructions.
    for harness in ["pi", "command_code", "opencode", "codex", "cline", "cursor", "grok_build", "agy", "kimi", "kiro", "kilo", "copilot", "crush", "omp"]:
        var source = FileAccess.get_file_as_string("res://src/agent/" + harness + "_agent_controller.gd")
        check("_game_prompt()" in source or harness in ["pi", "kilo"], harness + " uses the common Blender instructions")
    runner.queue_free()
    await process_frame
    print("Blender host: %d passed, %d failed" % [passed, failures])
    quit(1 if failures else 0)
