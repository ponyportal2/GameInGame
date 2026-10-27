extends SceneTree

# File operations are their own boundary: containment, link and .git rules apply
# to every read, write, move and delete, so they are exercised here without the
# git service, runner, supervisors or tool facade.

const WorkspaceOpsScript = preload("res://src/core/workspace_ops.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")

var failures = 0
var passed = 0

func _init() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
    if value:
        passed += 1; print("PASS: ", label)
    else:
        failures += 1; push_error("FAIL: " + label)

func check_eq(actual, expected, label: String) -> void:
    check(actual == expected, "%s (got %s, expected %s)" % [label, str(actual), str(expected)])

func run() -> void:
    _test_boundary()
    _test_large_file_read_and_patch_integrity()
    print("workspace ops: %d passed, %d failed" % [passed, failures])
    quit(1 if failures else 0)

func _test_boundary() -> void:
    var root = "user://games/tool-boundary-test"
    var outside = "user://games/tool-boundary-outside"
    var meta = MetadataStoreScript.new()
    meta._remove_tree_abs(ProjectSettings.globalize_path(root))
    meta._remove_tree_abs(ProjectSettings.globalize_path(outside))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outside))
    var ops = WorkspaceOpsScript.new()
    ops.workspace = root
    check(not ops.read_file("../host/credentials.json").ok, "tool cannot escape workspace")
    check(ops.write_file("main.gd", "extends Node\n").ok, "tool writes inside workspace")
    check(ops.write_file("keep.txt", "keep\n").ok, "tool writes a second workspace file")
    if OS.get_name() == "Windows":
        check(ops.write_file("locked/held.txt", "x").ok, "tool writes a file to hold open")
        var held = FileAccess.open(ProjectSettings.globalize_path(root.path_join("locked/held.txt")), FileAccess.READ)
        check(held != null, "recursive delete regression holds the file open")
        var refused_delete = ops.delete_path("locked")
        check(not refused_delete.ok and str(refused_delete.get("error", "")).contains("Delete failed ("), "a failed recursive delete reports its error code")
        check(str(refused_delete.get("error", "")).contains("retry"), "a failed recursive delete explains recovery")
        if held != null:
            held.close()
        check(ops.delete_path("locked").ok, "the same delete succeeds once the file is released")
    check(not ops.move_path("main.gd", "keep.txt").ok, "move refuses an existing destination")
    check(FileAccess.get_file_as_string(root.path_join("keep.txt")) == "keep\n", "a refused move keeps the destination intact")
    check(FileAccess.file_exists(root.path_join("main.gd")), "a refused move keeps the source")
    check(not ops.move_path("missing.gd", "moved.gd").ok, "move refuses a missing source")
    check(ops.move_path("main.gd", "sub/moved.gd").ok, "move creates the destination directory")
    check(ops.write_file("main.gd", "extends Node\n").ok, "tool restores the workspace entry point")
    check(not ops.write_file(".git/config", "x").ok, "tool cannot write reserved .git metadata")
    check(not ops.patch_file(".git/config", "a", "b").ok, "tool cannot patch reserved .git metadata")
    check(not ops.delete_path(".git").ok, "tool cannot delete reserved .git metadata")
    check(not ops.move_path("main.gd", ".git/main.gd").ok, "tool cannot move into reserved .git metadata")
    if OS.get_name() == "Windows":
        # Windows opens these as devices and strips trailing dots/spaces, so they
        # would reach outside the workspace or block on the console.
        for device_name in ["CON", "nul.txt", "aux.gd", "assets/CON.gd", "notes./main.gd", "notes /main.gd"]:
            check(PathUtils.safe_relative_path(device_name) == "", "path guard rejects " + device_name)
        check(PathUtils.safe_relative_path("assets/main.gd") == "assets/main.gd", "path guard keeps ordinary nested paths")
        check(not ops.read_file("CON").ok, "read rejects a Windows device name")
        check(not ops.write_file("nul.txt", "x").ok, "write rejects a Windows device name")
        check(not ops.write_file("assets/aux.gd", "x").ok, "write rejects a device name in a subdirectory")
        check(not ops.write_file("notes./main.gd", "x").ok, "write rejects a segment with a trailing dot")
        check(not ops.write_file("notes /main.gd", "x").ok, "write rejects a segment with a trailing space")
    _write_abs(ProjectSettings.globalize_path(outside.path_join("keep.txt")), "keep")
    var link = root.path_join("escape")
    if _create_dir_link(link, outside):
        check(not ops.read_file("escape/keep.txt").ok, "read rejects a path through a workspace link")
        check(not ops.write_file("escape/new.txt", "x").ok, "write rejects a path through a workspace link")
        check(not ops.delete_path("escape/keep.txt").ok, "delete rejects a path through a workspace link")
        check(not ops.delete_path("escape").ok, "delete rejects the workspace link itself")
        check(not ops.move_path("escape/keep.txt", "moved.txt").ok, "move rejects a source through a workspace link")
        check(not ops.move_path("main.gd", "escape/main.gd").ok, "move rejects a destination through a workspace link")
        check(not ops.list_files("escape").ok, "listing a linked directory is rejected")
        check(not ops.search_text("keep").get("matches", []).any(func(m): return "escape/" in str(m)), "search does not read through a link")
        check(FileAccess.file_exists(outside.path_join("keep.txt")), "linked outside file survives rejected tools")
        check(not FileAccess.file_exists(outside.path_join("new.txt")), "write through a link creates nothing outside")
        check(not FileAccess.file_exists(outside.path_join("moved.txt")), "move through a link moves nothing outside")
        var listing = ops.list_files()
        check(listing.ok and not listing.files.any(func(f): return str(f).begins_with("escape/")), "listing omits linked content")
        var container = root.path_join("delete-me")
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(container))
        var nested_link = container.path_join("escape")
        var nested_link_created = _create_dir_link(nested_link, outside)
        check(nested_link_created, "recursive delete fixture creates a nested directory link")
        if nested_link_created:
            check(ops.delete_path("delete-me").ok, "public delete removes a normal directory containing a link")
            check(FileAccess.file_exists(outside.path_join("keep.txt")), "public recursive delete preserves the outside sentinel")
            check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(container)), "public recursive delete removes its containing directory")
        # A link may be removed without following it into foreign content.
        var cleanup = "user://games/tool-boundary-cleanup"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cleanup))
        var linked_cleanup = cleanup.path_join("link")
        if _create_dir_link(linked_cleanup, outside):
            check(meta._remove_tree_abs(ProjectSettings.globalize_path(cleanup)) == OK, "tree removal accepts a link entry")
            check(FileAccess.file_exists(outside.path_join("keep.txt")), "tree removal never follows the link")
            check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cleanup)), "tree removal deletes the containing directory")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(link))
    else:
        check(false, "test fixture could create a directory link")
    meta._remove_tree_abs(ProjectSettings.globalize_path(root))
    meta._remove_tree_abs(ProjectSettings.globalize_path(outside))

func _create_dir_link(link: String, target: String) -> bool:
    var abs_link = ProjectSettings.globalize_path(link)
    var abs_target = ProjectSettings.globalize_path(target)
    var output: Array = []
    if OS.get_name() == "Windows":
        return OS.execute("cmd", ["/c", "mklink", "/J", abs_link.replace("/", "\\"), abs_target.replace("/", "\\")], output, true) == 0
    return OS.execute("ln", ["-s", abs_target, abs_link], output, true) == 0

func _test_large_file_read_and_patch_integrity() -> void:
    var root_dir = "user://games/large-file-tool-test"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_dir))
    var ops = WorkspaceOpsScript.new(root_dir)
    var large = ""
    for i in 800:
        if i == 10:
            large += "var TARGET_TOKEN = 1\n"
        else:
            large += "line_%04d = \"%s\"\n" % [i, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]
    large += "TAIL_SENTINEL\n"
    _write(root_dir.path_join("large.gd"), large)
    check(large.to_utf8_buffer().size() > 30000, "large-file regression fixture exceeds old 30 KB read cap")

    var head = ops.read_file("large.gd", 1, 25)
    check(bool(head.get("ok", false)), "chunked read succeeds")
    check(bool(head.get("truncated", false)), "chunked read explicitly reports that more file content exists")
    check_eq(int(head.get("line_start", 0)), 1, "chunked read reports first returned line")
    check_eq(int(head.get("line_end", 0)), 25, "chunked read respects requested line limit")
    check_eq(int(head.get("next_offset", 0)), 26, "chunked read exposes continuation offset")

    var tail = ops.read_file("large.gd", 790, 30)
    check("TAIL_SENTINEL" in str(tail.get("content", "")), "chunked read can retrieve the tail of a large file")

    var before = FileAccess.get_file_as_string(root_dir.path_join("large.gd"))
    var patched = ops.patch_file("large.gd", "var TARGET_TOKEN = 1", "var TARGET_TOKEN = 2")
    var after = FileAccess.get_file_as_string(root_dir.path_join("large.gd"))
    check(bool(patched.get("ok", false)), "patch_file accepts an exact unique edit in a large file")
    check("var TARGET_TOKEN = 2" in after, "patch_file applies requested edit")
    check("TAIL_SENTINEL" in after, "patch_file preserves content beyond the read preview window")
    check_eq(after.length(), before.length(), "equal-length patch preserves the complete file length")
    check_eq(int(patched.get("bytes_before", -1)), before.to_utf8_buffer().size(), "patch result reports original full-file size")
    check_eq(int(patched.get("bytes_after", -1)), after.to_utf8_buffer().size(), "patch result reports resulting full-file size")

    var meta = MetadataStoreScript.new()
    meta._remove_tree_abs(ProjectSettings.globalize_path(root_dir))

func _write_abs(path: String, content: String) -> void:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var f = FileAccess.open(path, FileAccess.WRITE); f.store_string(content); f.close()

func _write(path: String, content: String) -> void:
    var f = FileAccess.open(path, FileAccess.WRITE); f.store_string(content); f.close()
