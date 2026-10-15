extends RefCounted
## Runtime asset access independent of script/cache paths and editor imports.
## This is a convenience API, not a sandbox for generated GDScript.

var workspace: String

func _init(directory: String) -> void:
    workspace = ProjectSettings.globalize_path(directory).simplify_path()

func path(relative: String) -> String:
    var normalized = relative.replace("\\", "/")
    if normalized.is_empty() or normalized.is_absolute_path() or ":" in normalized:
        return ""
    normalized = normalized.simplify_path()
    if normalized == ".." or normalized.begins_with("../"):
        return ""
    return workspace.path_join(normalized)

func load_glb(relative: String) -> Node3D:
    var filename = path(relative)
    if filename == "" or filename.get_extension().to_lower() != "glb" or not FileAccess.file_exists(filename):
        push_error("GameSmith GLB asset not found: " + relative)
        return null
    var document = GLTFDocument.new()
    var state = GLTFState.new()
    var error = document.append_from_file(filename, state)
    if error != OK:
        push_error("GameSmith GLB load failed (%d): %s" % [error, relative])
        return null
    return document.generate_scene(state)
