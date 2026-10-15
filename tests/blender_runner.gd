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
    check(job.ok and job.state == "awaiting_approval", "Python start waits for player approval")
    check(tools.blender_supervisor.runs[job.run_id].pid == -1, "no native process starts before player approval")
    tools.blender_supervisor.approve(job.run_id)
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
    # Tool arguments cannot authorize execution or reuse a declined review.
    job = tools.blender({"action": "start", "script": "build.py", "approved": true})
    check(job.state == "awaiting_approval", "model-supplied approval flag is ignored")
    check(not tools.blender({"action": "approve", "run_id": job.run_id}).ok, "approval is not an agent tool action")
    tools.blender({"action": "stop", "run_id": job.run_id})
    check(not tools.blender_supervisor.approve(job.run_id).ok, "declined approvals cannot be replayed")
    job = tools.blender({"action": "start", "script": "build.py"})
    tools.write_file("build.py", "print('changed after review')\n")
    tools.blender_supervisor.approve(job.run_id)
    result = await wait_job(job.run_id)
    check(not result.ok and "changed" in result.get("error", ""), "changed script fails before Blender executes")
    # Every controller inherits the same thin Blender instructions.
    for harness in ["pi", "command_code", "opencode", "codex", "cline", "cursor", "grok_build", "agy", "kimi", "kiro", "kilo", "copilot", "crush", "omp"]:
        var source = FileAccess.get_file_as_string("res://src/agent/" + harness + "_agent_controller.gd")
        check("_game_prompt()" in source or harness in ["pi", "kilo"], harness + " uses the common Blender instructions")
    # All native harnesses use the same host wait; reload auto-approval cannot
    # authorize Python. No actual native harness/provider is needed for this.
    var settings = preload("res://src/core/metadata_store.gd").new()
    var defaults = settings.global_settings()
    defaults.auto_approve_reloads = true
    settings.save_global_settings(defaults)
    for harness in ["pi", "command_code", "opencode", "codex", "cline", "cursor", "grok_build", "agy", "kimi", "kiro", "kilo", "copilot", "crush", "omp"]:
        var controller = load("res://src/agent/" + harness + "_agent_controller.gd").new()
        controller.tools = tools
        controller.bridge_dir = ProjectSettings.globalize_path("user://blender-approval-bridge/" + harness)
        DirAccess.make_dir_recursive_absolute(controller.bridge_dir)
        controller._dispatch_host_request({"id": "approval", "command": "blender", "args": {"action": "start", "script": "build.py"}}, controller.bridge_dir)
        var pending = controller.pending_blender_commands
        var response = controller.bridge_dir.path_join("response-approval.json")
        check(pending.size() == 1 and not FileAccess.file_exists(response), harness + " keeps tool call pending for Python approval")
        var id = str(pending[0].run_id) if not pending.is_empty() else ""
        if id != "":
            check(tools.blender_supervisor.runs[id].pid == -1, harness + " never runs Python under reload auto-approval")
            tools.blender({"action": "stop", "run_id": id})
            controller._service_pending_blender_commands()
            var reply = JsonStore.read_dict(response)
            check(not reply.get("ok", true) and reply.get("state") == "cancelled", harness + " delivers player rejection to native tool")
        controller.free()
    # Pre-MCP permission authorization returns only after player approval. Its
    # private receipt is bound to this operation and exact request arguments.
    var controller = load("res://src/agent/cline_agent_controller.gd").new()
    controller.tools = tools
    controller.busy = true
    controller.bridge_dir = ProjectSettings.globalize_path("user://blender-preapproval")
    DirAccess.make_dir_recursive_absolute(controller.bridge_dir)
    var args = {"action": "start", "script": "build.py"}
    var auth = {"id": "auth", "command": "authorize_blender", "args": {"token": "private-token", "blender_args": args}}
    controller._dispatch_host_request(auth, controller.bridge_dir)
    var auth_job: String = controller.pending_blender_commands[0].run_id
    check(not FileAccess.file_exists(controller.bridge_dir.path_join("response-auth.json")), "ACP permission holds before finite MCP window")
    OS.set_environment("GAMESMITH_BLENDER_BIN", "C:/missing-gamesmith-blender.exe")
    tools.blender_supervisor.approve(auth_job)
    await wait_job(auth_job) # An immediate execution failure still belongs in the MCP result.
    controller._service_pending_blender_commands()
    check(controller.blender_grants.has("private-token"), "approved job produces a private operation-bound grant")
    var granted = args.duplicate()
    granted.approval_token = "private-token"
    controller._dispatch_host_request({"id": "consume", "command": "blender", "args": granted}, controller.bridge_dir)
    check(not controller.blender_grants.has("private-token") and controller.pending_blender_commands.is_empty(), "MCP consumes approved job without another launch or approval")
    var executed = JsonStore.read_dict(controller.bridge_dir.path_join("response-consume.json"))
    check(not executed.get("ok", true) and "Blender" in executed.get("error", ""), "approved execution failures reach the actual MCP tool result")
    controller._dispatch_host_request({"id": "replay", "command": "blender", "args": granted}, controller.bridge_dir)
    check(not JsonStore.read_dict(controller.bridge_dir.path_join("response-replay.json")).get("ok", true), "Blender grant replay is rejected")
    controller.blender_grants["changed"] = {"operation_id": controller.operation_id, "bridge_dir": controller.bridge_dir, "run_id": auth_job, "args": args}
    controller._dispatch_host_request({"id": "changed", "command": "blender", "args": {"action": "start", "script": "other.py", "approval_token": "changed"}}, controller.bridge_dir)
    check(not JsonStore.read_dict(controller.bridge_dir.path_join("response-changed.json")).get("ok", true) and not controller.blender_grants.has("changed"), "changed arguments burn and reject the Blender grant")
    controller.blender_grants["stale"] = {"operation_id": controller.operation_id - 1, "bridge_dir": controller.bridge_dir, "run_id": auth_job, "args": args}
    var stale = args.duplicate()
    stale.approval_token = "stale"
    controller._dispatch_host_request({"id": "stale", "command": "blender", "args": stale}, controller.bridge_dir)
    check(not JsonStore.read_dict(controller.bridge_dir.path_join("response-stale.json")).get("ok", true), "previous operation cannot authorize a Blender request")
    controller.restart_runtime()
    check(controller.blender_grants.is_empty(), "runtime retirement clears Blender grants")
    controller.free()
    await wait_job(auth_job)
    if previous == "": OS.unset_environment("GAMESMITH_BLENDER_BIN")
    else: OS.set_environment("GAMESMITH_BLENDER_BIN", previous)
    # Exercise actual UI controls and source/hash display.
    var app = load("res://main.tscn").instantiate()
    root.add_child(app)
    await process_frame
    app.name_edit.text = "Blender approval UI"
    app._create_game()
    app.tools.write_file("ui.py", "print('review this source')\n")
    job = app.tools.blender({"action": "start", "script": "ui.py"})
    check(app.blender_dialog.visible and "ui.py" in app.blender_review_label.text and "SHA-256" in app.blender_review_label.text and "review this source" in app.blender_review_source.text, "player sees script path, hash and source")
    app._decide_blender(false)
    check(not app.blender_dialog.visible and app.tools.blender({"action": "status", "run_id": job.run_id}).state == "cancelled", "UI Cancel declines without executing")
    job = app.tools.blender({"action": "start", "script": "ui.py"})
    app.agent.restart_runtime()
    check(not app.blender_dialog.visible and not app.tools.blender_supervisor.approve(job.run_id).ok, "runtime retirement clears approval and invalidates Run")
    OS.set_environment("GAMESMITH_BLENDER_BIN", "C:/missing-gamesmith-blender.exe")
    job = app.tools.blender({"action": "start", "script": "ui.py"})
    app._decide_blender(true)
    check(not app.blender_dialog.visible and app.tools.blender_supervisor.runs[job.run_id].pid > 1, "UI Run launches the approved job")
    var old_tools = tools
    tools = app.tools
    await wait_job(job.run_id)
    tools = old_tools
    if previous == "": OS.unset_environment("GAMESMITH_BLENDER_BIN")
    else: OS.set_environment("GAMESMITH_BLENDER_BIN", previous)
    app._show_library()
    app.queue_free()
    runner.queue_free()
    await process_frame
    print("Blender host: %d passed, %d failed" % [passed, failures])
    quit(1 if failures else 0)
