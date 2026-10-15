# Blender assets in GameSmith

Use the GameSmith `blender` tool (your harness adds its normal tool prefix). No shell, Blender UI or Blender MCP server is needed.

1. Write a reusable workspace-relative `.py` file using your ordinary write/edit tool. It runs with `bpy`, the workspace as cwd, and `GAMESMITH_WORKSPACE` set. Use absolute output paths derived from `Path.cwd()`. Keep inputs, exports and previews inside the game workspace. Python is executable code, not a filesystem sandbox.
2. `blender(action="start", script="art/build.py", render="art/preview.png")` waits for the player's **Run script / Cancel** decision. Each run requires approval unless the player enabled **Automatically approve Blender scripts** in Settings. That separate setting defaults off and is independent of reload auto-approval. The player sees the path, full UTF-8 source (up to 256 KiB) and SHA-256. Approval runs a private snapshot; changes to the original before launch or to the snapshot are rejected. Imported modules and other files are not frozen. Do not try to approve through tool arguments or bypass a rejection. After approval the background job returns a `run_id`. Optional `blend="art/source.blend"` opens an existing scene before running the script. To inspect an existing blend, omit `script`; embedded auto-run scripts remain disabled and this does not request Python approval. `render` is optional; if supplied, your scene must have a camera, lights and sensible render settings.
3. Poll `blender(action="status", run_id=...)` until `completed`, `failed` or `cancelled`. Inspect `log_tail`, exit status and the automatic scene report (objects, dimensions, mesh counts, materials, camera). A failed job is yours to fix. `stop` cancels the process tree; the chat Stop button also cancels Blender work. Do not start another job until the previous one has exited.
4. `blender(action="inspect", path="art/preview.png")` returns the PNG as image content plus dimensions. This requires a vision-capable selected model and harness image support. If vision is unavailable, use the scene report and explain that visual appearance was not verified. Do not claim to have viewed JSON/base64 as an image. Previews must be PNG, at most 8 MiB, 4096 per dimension and 4 megapixels. Prefer 512–1024 px.
5. Improve the asset from the render/report, rerun and inspect. Save editable source with `bpy.ops.wm.save_as_mainfile(filepath=str(Path.cwd()/"art/source.blend"))`. Export game models with `bpy.ops.export_scene.gltf(filepath=str(Path.cwd()/"art/model.glb"), export_format='GLB')`. Prefer modest mesh/material counts and embedded GLB textures. Never depend on Godot importing `.blend` or on an editor-generated `.import` cache.
6. GameSmith runs generated games without Godot's editor import pipeline. Instantiate GLB at runtime with `GLTFDocument` and `GLTFState`, not `preload("model.glb")`:

```gdscript
var document = GLTFDocument.new()
var state = GLTFState.new()
var err = document.append_from_file(get_script().resource_path.get_base_dir().path_join("art/model.glb"), state)
if err == OK:
    add_child(document.generate_scene(state))
```

For rendered sprites use `Image.load_from_file(absolute_png_path)` and `ImageTexture.create_from_image(image)`. Do not invent a `.tscn` dependency. After integration run the normal headless game test, inspect its diagnostics, stop it, then request reload before handoff.

Background scripts should use data APIs and operators that do not need a UI area. A small CPU preview is portable: `scene.render.engine='CYCLES'`, `scene.cycles.device='CPU'`, `scene.cycles.samples=8`, set resolution and `resolution_percentage=100`, configure a camera pointing at the asset and lights. Do not require GPU availability. Blender API names vary by installed version; the report/log identifies the actual version. `--factory-startup`, private user config and disabled automatic scripts avoid depending on the player's open Blender scene/preferences. Deliberately executed bpy scripts can still run arbitrary Python: keep all operations scoped to this game.
