extends SceneTree

const Policy = preload("res://src/core/script_load_policy.gd")
const Runner = preload("res://src/core/game_runner.gd")
const Config = preload("res://src/pi/pi_runtime_config.gd")
var passed = 0
var failed = 0

func _init() -> void:
    call_deferred("run")

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        push_error("FAIL: " + label)

func write_text(path: String, source: String) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_string(source)
    file.close()

func run() -> void:
    for source in [
        "const H = preload('helper.gd')",
        "extends 'base.gd'",
        "load('texture.png')",
        "ResourceLoader.load(path, 'Texture2D')",
        "ResourceLoader.load('uid://asset', 'Texture2D')",
        "ResourceLoader.load_threaded_request(path, 'PackedScene')",
        "# load('helper.gd')\nvar text = \"load('other.gd')\"",
        "var text = '''\nResourceLoader.load('helper.gd')\n'''",
        "var text = \"escaped \\\"load('helper.gd')\\\"\"",
        "func load(path): pass",
        "reload('helper.gd')",
        "load('asset(with,comma).png')",
        "ResourceLoader.load(make_path([1, 2]), 'Texture2D')",
    ]:
        check(Policy.first_violation(source).is_empty(), "allows: " + source)
    for source in [
        "load('helper.gd')",
        "load('HELPER.GD')",
        "ResourceLoader.load('helper.gdc')",
        "ResourceLoader.load_threaded_request('helper.gd')",
        "ResourceLoader.load_threaded_get('helper.gd')",
        "loader.load('helper.cs')",
        "load(path)",
        "load('uid://unknown')",
        "load('extensionless')",
        "load('boss' + '.gd')",
        "ResourceLoader.load(path, 'Resource')",
        "ResourceLoader.load(path, 'Script')",
        "ResourceLoader.load('asset.dat', 'GDScript')",
        "load(r'helper.gd')",
        "load('helper.gd', 'Texture2D')",
    ]:
        check(not Policy.first_violation(source).is_empty(), "rejects: " + source)
    var multiline = "# example\nvar text = '''\nload('example.gd')\n'''\nResourceLoader.load(\n    'helper.gd'\n)"
    check(Policy.first_violation(multiline).get("line") == 5, "reports call line after multiline strings")
    var prompt = Config._game_prompt()
    check("Use preload() for helper scripts" in prompt and "Script inheritance" in prompt and "computed asset paths" in prompt, "model instructions describe script and asset loading policy")
    await test_reload_gate()
    print("SCRIPT LOAD POLICY TESTS: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)

func test_reload_gate() -> void:
    var ws = "user://script-policy-%d" % Time.get_ticks_usec()
    var helper = ws.path_join("helper.gd")
    var main = ws.path_join("main.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 12\n")
    write_text(main, "extends Node\nconst H = preload('helper.gd')\nfunc probe(): return H.new().value()\n")
    var runner = Runner.new()
    root.add_child(runner)
    check(runner.load_game(ws).ok, "accepts relative preload")
    var old_game = runner.active_game
    var old_helper = ResourceLoader.get_cached_ref(helper)
    write_text(helper, "extends RefCounted\nfunc value(): return 99\n")
    write_text(ws.path_join("nested/unused.gd"), "extends RefCounted\nfunc later(): return load('boss.gd')\n")
    var rejected = runner.load_game(ws)
    check(not rejected.ok and "unused.gd:2:" in rejected.error, "checks nested unused scripts and reports file/line")
    check(runner.active_game == old_game and old_game.probe() == 12, "policy failure preserves accepted game code")
    check(ResourceLoader.get_cached_ref(helper) == old_helper, "policy failure leaves dependency cache intact")
    write_text(ws.path_join("nested/unused.gd"), "extends RefCounted\n")
    write_text(ws.path_join("nested/uppercase.GD"), "extends RefCounted\nfunc later(): return load('boss.gd')\n")
    rejected = runner.load_game(ws)
    check(not rejected.ok and "uppercase.GD:2:" in rejected.error, "checks uppercase script extensions on Windows")
    write_text(ws.path_join("nested/uppercase.GD"), "extends RefCounted\n")
    write_text(ws.path_join(".git/ignored.gd"), "load('ignored.gd')")
    write_text(ws.path_join(".godot/ignored.gd"), "load('ignored.gd')")
    check(runner.load_game(ws).ok and runner.active_game.probe() == 99, "fixed candidate refreshes helper and ignores metadata directories")
    runner.queue_free()
    await process_frame
    await process_frame
