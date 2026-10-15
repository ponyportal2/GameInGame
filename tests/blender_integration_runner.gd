extends "res://tests/blender_runner.gd"

func approved_start(args: Dictionary) -> Dictionary:
    var result = tools.execute("blender", args)
    check(result.get("state") == "awaiting_approval" and tools.blender_supervisor.runs[result.run_id].pid == -1, "real Python job waits for player decision")
    tools.blender_supervisor.approve(result.run_id)
    return result

func run() -> void:
    var workspace = "user://games/Blender live acceptance"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
    var runner = GameRunner.new()
    root.add_child(runner)
    tools = GameTools.new(workspace, runner)
    var guide = tools.blender({"action": "guide"})
    tools.write_file("build.py", str(guide.example_script) + "\nimport os\nassert 'GAMESMITH_TEST_SECRET' not in os.environ\nassert 'PYTHONPATH' not in os.environ\nassert Path(__file__).name == 'approved.py'\nscene.render.resolution_x = 96\nscene.render.resolution_y = 96\n")
    var previous_secret = OS.get_environment("GAMESMITH_TEST_SECRET")
    OS.set_environment("GAMESMITH_TEST_SECRET", "must not reach Blender")
    var metadata = MetadataStore.new()
    var settings = metadata.global_settings()
    settings.auto_approve_blender_scripts = true
    metadata.save_global_settings(settings)
    var job: Dictionary = tools.execute("blender", {"action": "start", "script": "build.py", "render": "art/preview.png"})
    check(job.get("state") == "starting", "installed Blender starts automatically when the separate setting is enabled")
    settings.auto_approve_blender_scripts = false
    metadata.save_global_settings(settings)
    check(job.ok, "installed Blender starts through shared host tool")
    check(not tools.execute("blender", {"action": "start", "script": "build.py"}).ok, "concurrent job is rejected")
    var result: Dictionary = await wait_job(job.run_id, 90.0)
    print("BLENDER RESULT: ", JSON.stringify(result))
    check(result.get("ok", false) and result.get("state") == "completed", "actual bpy script exports and renders successfully")
    if previous_secret == "": OS.unset_environment("GAMESMITH_TEST_SECRET")
    else: OS.set_environment("GAMESMITH_TEST_SECRET", previous_secret)
    check(result.get("report", {}).get("object_count") == 9, "automatic scene report inspects actual Blender scene")
    check(FileAccess.file_exists(workspace.path_join("art/model.glb")), "GLB asset exists")
    check(FileAccess.file_exists(workspace.path_join("art/source.blend")), "editable blend source exists")
    result = tools.execute("blender", {"action": "inspect", "path": "art/preview.png"})
    check(result.get("ok", false) and result.get("width") == 96 and result.has("image_base64"), "real rendered PNG is available for visual review")
    print("BLENDER PREVIEW: ", ProjectSettings.globalize_path(workspace.path_join("art/preview.png")))
    var detailed: Dictionary = tools.blender({"action": "status", "run_id": job.run_id, "details": true})
    var head_report: Dictionary = {}
    for obj in detailed.get("report", {}).get("objects", []):
        if obj.name == "Head": head_report = obj
    check(head_report.get("parent") == "HeadPivot" and abs(float(head_report.get("world_location", [0, 0, 0])[2]) - 2.4) < 0.01, "Report includes animation hierarchy and world-space positions")
    check(detailed.get("report", {}).get("artifacts", []).size() >= 3, "Report lists exported GLB, source blend and preview artifacts")
    tools.write_file("main.gd", """extends Node3D
var asset_ok := false
var axes_ok := false
var hierarchy_ok := false
func _ready():
    var model = get_meta("gamesmith_assets").load_glb("art/model.glb")
    if model == null: return
    model.name = "ImportedAsset"
    add_child(model)
    var right = model.find_child("RightMarker", true, false)
    var front = model.find_child("FrontMarker", true, false)
    var head = model.find_child("Head", true, false)
    asset_ok = model.find_child("Body", true, false) != null
    axes_ok = right != null and front != null and right.global_position.distance_to(Vector3(2, 1, 0)) < 0.01 and front.global_position.distance_to(Vector3(0, 1, 1)) < 0.01
    hierarchy_ok = head != null and head.get_parent().name == "HeadPivot" and model.find_child("PreviewCamera", true, false) == null and model.find_child("PreviewLight", true, false) == null
    var camera = Camera3D.new()
    add_child(camera)
    camera.position = Vector3(5, 4, 7)
    camera.look_at(Vector3(0.5, 1, 0))
    var light = DirectionalLight3D.new()
    add_child(light)
    light.rotation_degrees = Vector3(-40, -30, 0)
""")
    result = runner.load_game(workspace)
    check(result.ok and runner.active_game.asset_ok, "Host helper consumes Blender GLB without editor imports")
    check(result.ok and runner.active_game.axes_ok, "Asymmetric exported markers prove Blender-to-Godot axes")
    check(result.ok and runner.active_game.hierarchy_ok, "Export preserves animation pivots and excludes preview camera/lights")
    result = runner.load_game(workspace)
    check(result.ok and runner.active_game.axes_ok, "GLB helper survives a second reload")
    var test: Dictionary = tools.execute("start_test_game", {"mode": "headless"})
    var deadline = Time.get_ticks_msec() + 15000
    while Time.get_ticks_msec() < deadline:
        result = tools.execute("read_test_log", {"run_id": test.run_id})
        if result.get("load_result", {}).get("ok", false) or result.get("state") == "exited": break
        await create_timer(0.1).timeout
    check(result.get("load_result", {}).get("ok", false), "integrated Blender asset passes separate headless game test")
    tools.execute("stop_test_game", {"run_id": test.run_id})
    while Time.get_ticks_msec() < deadline and tools.tests().status(test.run_id).get("state") != "exited":
        await create_timer(0.05).timeout
    settings.allow_rendered_tests = true
    metadata.save_global_settings(settings)
    test = tools.execute("start_test_game", {"mode": "rendered"})
    deadline = Time.get_ticks_msec() + 15000
    while Time.get_ticks_msec() < deadline and tools.tests().status(test.run_id).get("state") == "starting":
        await create_timer(0.05).timeout
    var action = tools.execute("test_game_action", {"run_id": test.run_id, "action": "screenshot"})
    result = action
    while result.get("pending", false) and Time.get_ticks_msec() < deadline:
        await create_timer(0.05).timeout
        result = tools.execute("test_game_action", {"run_id": test.run_id, "action": "poll", "action_id": action.action_id})
    var screenshot = Image.new()
    check(result.get("ok", false) and screenshot.load_png_from_buffer(Marshalls.base64_to_raw(result.get("image_base64", ""))) == OK, "Imported Blender asset produces a real rendered Godot screenshot")
    if not screenshot.is_empty():
        var varied := false
        for x in range(0, screenshot.get_width(), 32):
            for y in range(0, screenshot.get_height(), 32):
                if screenshot.get_pixel(x, y) != screenshot.get_pixel(0, 0): varied = true
        check(varied, "Godot screenshot contains rendered geometry rather than a flat background")
        var screenshot_path = ProjectSettings.globalize_path(workspace.path_join("art/godot-preview.png"))
        screenshot.save_png(screenshot_path)
        print("GODOT PREVIEW: ", screenshot_path)
    tools.execute("stop_test_game", {"run_id": test.run_id})
    settings.allow_rendered_tests = false
    metadata.save_global_settings(settings)
    # Reopen the native .blend independently, with no script replay.
    job = tools.execute("blender", {"action": "start", "blend": "art/source.blend"})
    result = await wait_job(job.run_id, 30.0)
    check(result.get("ok", false) and result.get("report", {}).get("object_count") == 9, "saved blend can be reopened and inspected")
    tools.write_file("bad.py", "raise RuntimeError('deliberate bpy failure')\n")
    job = approved_start({"action": "start", "script": "bad.py"})
    result = await wait_job(job.run_id, 30.0)
    check(not result.get("ok", true) and result.get("exit_code") == 1 and "deliberate bpy failure" in result.get("log_tail", ""), "Python failures return exit code and traceback to agent")
    tools.write_file("wait.py", "import time\nprint('WAITING', flush=True)\ntime.sleep(120)\n")
    job = approved_start({"action": "start", "script": "wait.py"})
    deadline = Time.get_ticks_msec() + 20000
    while Time.get_ticks_msec() < deadline:
        result = tools.execute("blender", {"action": "status", "run_id": job.run_id})
        if "WAITING" in result.get("log_tail", ""): break
        await create_timer(0.1).timeout
    var pid = int(result.get("pid", -1))
    tools.execute("blender", {"action": "stop", "run_id": job.run_id})
    result = await wait_job(job.run_id, 10.0)
    check(result.get("state") == "cancelled" and pid > 0 and not OS.is_process_running(pid), "Stop terminates real Blender and reports cancellation")
    job = approved_start({"action": "start", "script": "wait.py"})
    deadline = Time.get_ticks_msec() + 20000
    while Time.get_ticks_msec() < deadline:
        result = tools.execute("blender", {"action": "status", "run_id": job.run_id})
        if "WAITING" in result.get("log_tail", ""): break
        await create_timer(0.1).timeout
    pid = int(result.get("pid", -1))
    var controller = preload("res://src/agent/pi_agent_controller.gd").new()
    controller.tools = tools
    controller.restart_runtime()
    result = await wait_job(job.run_id, 10.0)
    check(result.get("state") == "cancelled" and pid > 0 and not OS.is_process_running(pid), "shared controller retirement also cancels real Blender work")
    controller.free()
    job = approved_start({"action": "start", "script": "wait.py"})
    deadline = Time.get_ticks_msec() + 20000
    while Time.get_ticks_msec() < deadline:
        result = tools.blender({"action": "status", "run_id": job.run_id})
        if "WAITING" in result.get("log_tail", "") and result.get("identity", {}).get("birth", "") != "": break
        await create_timer(0.1).timeout
    pid = int(result.get("pid", -1))
    var supervisor_pid = int(tools.blender_supervisor.runs[job.run_id].pid)
    OS.kill(supervisor_pid) # Deliberately kill just Node, bypassing its EOF cleanup.
    result = await wait_job(job.run_id, 20.0)
    check(result.get("state") == "failed" and pid > 0 and not OS.is_process_running(pid), "supervisor crash cleans up the verified real Blender process")
    check(not tools.blender_supervisor.has_running(), "orphan cleanup releases the next Blender job")
    runner.queue_free()
    await process_frame
    print("Blender live: %d passed, %d failed" % [passed, failures])
    quit(1 if failures else 0)
