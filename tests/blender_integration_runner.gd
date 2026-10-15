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
    tools.write_file("build.py", """import bpy
from pathlib import Path
from mathutils import Vector
import os
assert 'GAMESMITH_TEST_SECRET' not in os.environ
assert 'PYTHONPATH' not in os.environ
assert Path(__file__).name == 'approved.py'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add(size=2)
obj=bpy.context.object
obj.name='GameSmithTower'
obj.scale=(0.7,0.7,1.5)
mat=bpy.data.materials.new('Blue')
mat.diffuse_color=(0.05,0.3,0.8,1)
mat.use_nodes=True
mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(0.05,0.3,0.8,1)
obj.data.materials.append(mat)
bpy.ops.object.camera_add(location=(4,-6,4))
cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.camera=cam
bpy.ops.object.light_add(type='AREA',location=(1,-4,6))
bpy.context.object.data.energy=700
bpy.context.object.data.shape='DISK'
bpy.context.object.data.size=5
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=4
scene.render.resolution_x=96
scene.render.resolution_y=96
scene.render.resolution_percentage=100
out=Path.cwd()/'art'
out.mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'source.blend'))
bpy.ops.export_scene.gltf(filepath=str(out/'tower.glb'),export_format='GLB')
""")
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
    check(result.get("report", {}).get("object_count") == 3, "automatic scene report inspects actual Blender scene")
    check(FileAccess.file_exists(workspace.path_join("art/tower.glb")), "GLB asset exists")
    check(FileAccess.file_exists(workspace.path_join("art/source.blend")), "editable blend source exists")
    result = tools.execute("blender", {"action": "inspect", "path": "art/preview.png"})
    check(result.get("ok", false) and result.get("width") == 96 and result.has("image_base64"), "real rendered PNG is available for visual review")
    print("BLENDER PREVIEW: ", ProjectSettings.globalize_path(workspace.path_join("art/preview.png")))
    tools.write_file("main.gd", """extends Node3D
var asset_ok := false
func _ready():
    var document = GLTFDocument.new()
    var state = GLTFState.new()
    var err = document.append_from_file(get_script().resource_path.get_base_dir().path_join("art/tower.glb"), state)
    if err != OK:
        push_error("GLB failed to load")
        return
    var model = document.generate_scene(state)
    add_child(model)
    asset_ok = model.find_child("GameSmithTower", true, false) != null
""")
    result = runner.load_game(workspace)
    check(result.ok and runner.active_game.asset_ok, "Godot consumes Blender GLB without editor imports")
    var test: Dictionary = tools.execute("start_test_game", {"mode": "headless"})
    var deadline = Time.get_ticks_msec() + 15000
    while Time.get_ticks_msec() < deadline:
        result = tools.execute("read_test_log", {"run_id": test.run_id})
        if result.get("load_result", {}).get("ok", false) or result.get("state") == "exited": break
        await create_timer(0.1).timeout
    check(result.get("load_result", {}).get("ok", false), "integrated Blender asset passes separate headless game test")
    tools.execute("stop_test_game", {"run_id": test.run_id})
    # Reopen the native .blend independently, with no script replay.
    job = tools.execute("blender", {"action": "start", "blend": "art/source.blend"})
    result = await wait_job(job.run_id, 30.0)
    check(result.get("ok", false) and result.get("report", {}).get("object_count") == 3, "saved blend can be reopened and inspected")
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
