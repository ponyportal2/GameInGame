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
    test_api_matrix()
    for source in [
        "const H = preload('helper.gd')",
        "extends 'base.gd'",
        "load('texture.png')",
        "# load('helper.gd')\nvar text = \"load('other.gd')\"",
        "var text = '''\nResourceLoader.load('helper.gd')\n'''",
        "var text = 'multiline example:\nload(\"helper.gd\")\n'",
        "var text = \"escaped \\\"load('helper.gd')\\\"\"",
        "func load(path): pass",
        "reload('helper.gd')",
        "load('asset(with,comma).png')",
        "ResourceLoader.load('texture.png', 'Texture2D', 1)",
        "ConfigFile.new().load('user://settings.cfg')",
        "config.load('user://settings.cfg')",
        "image.load('user://capture.webp')",
        "inventory.load('save.dat')",
        "thing.load('scene.tres')",
        "thing.load(path, 'GDScript')",
        "thing.load_threaded_request('scene.tscn')",
        "thing.load_threaded_get(path)",
        "load_threaded_request('helper.gd')",
        "load_threaded_get('helper.gd')",
        "loader.load('helper.cs')",
        "var loader = ResourceLoader\nloader.load('helper.gd')",
        "owner.ResourceLoader.load('helper.gd')",
        "'ResourceLoader'.load('helper.gd')",
    ]:
        check(Policy.first_violation(source).is_empty(), "allows: " + source)
    for source in [
        "load('helper.gd')",
        "load('HELPER.GD')",
        "ResourceLoader.load('helper.gdc')",
        "ResourceLoader.load_threaded_request('helper.gd')",
        "ResourceLoader.load_threaded_get('helper.gd')",
        "load(path)",
        "load('uid://unknown')",
        "load('extensionless')",
        "load('boss' + '.gd')",
        "ResourceLoader.load(path, 'Resource')",
        "ResourceLoader.load(path, 'Script')",
        "ResourceLoader.load('asset.dat', 'GDScript')",
        "load(r'helper.gd')",
        "ResourceLoader.load(make_path([1, 2]), 'Texture2D')",
        "func f():\n    var marker = '.'\n    load('helper.gd')",
        "func f():\n    var marker = 'func'\n    load('helper.gd')",
        "func f():\n    var marker = '.'\n    ResourceLoader.load('helper.gd')",
    ]:
        check(not Policy.first_violation(source).is_empty(), "rejects: " + source)
    var multiline = "# example\nvar text = '''\nload('example.gd')\n'''\nResourceLoader.load(\n    'helper.gd'\n)"
    check(Policy.first_violation(multiline).get("line") == 5, "reports call line after multiline strings")
    var prompt = Config._game_prompt()
    check("Use preload() for helper scripts" in prompt and "Script inheritance" in prompt and "literal PNG/JPG/JPEG/WAV/OGG" in prompt and "outside the static check" in prompt, "model instructions describe precise loading policy and enforcement limits")
    await test_reload_gate()
    print("SCRIPT LOAD POLICY TESTS: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)

func test_api_matrix() -> void:
    for api in ["load", "ResourceLoader.load", "ResourceLoader.load_threaded_request", "ResourceLoader.load_threaded_get"]:
        var accepts_hint = api in ["ResourceLoader.load", "ResourceLoader.load_threaded_request"]
        for extension in ["png", "jpg", "jpeg", "wav", "ogg"]:
            for spelling in [extension, extension.to_upper()]:
                var source = "%s('asset.%s')" % [api, spelling]
                check(Policy.first_violation(source).is_empty(), "approved asset: " + source)
        for path in ["'helper.gd'", "'helper.GD'", "'helper.gdc'", "'helper.cs'", "'scene.tscn'", "'scene.scn'", "'asset.tres'", "'asset.res'", "'asset.mesh'", "'asset.material'", "'asset.svg'", "'asset.ttf'", "'asset.otf'", "'asset.bin'", "'uid://asset.png'", "'extensionless'", "path", "'asset.' + 'png'", "'helper.gd\n'"]:
            var source = "%s(%s)" % [api, path]
            check(not Policy.first_violation(source).is_empty(), "unsupported path: " + source)
            if accepts_hint:
                source = "%s(%s, 'Texture2D')" % [api, path]
                check(not Policy.first_violation(source).is_empty(), "hint cannot override path: " + source)
        if accepts_hint:
            for hint in ["Script", "GDScript"]:
                var source = "%s('asset.png', '%s')" % [api, hint]
                check(not Policy.first_violation(source).is_empty(), "script hint: " + source)
        for arguments in ["'helper.gd'", "'helper.gd']", "[path)", "'helper.gd", "'''helper.gd", "", ", 'helper.gd')"]:
            var source = "%s(%s" % [api, arguments]
            check(Policy.first_violation(source).is_empty(), "malformed call defers: " + source)
    for source in ["load('helper.gd', 'Texture2D')", "ResourceLoader.load_threaded_get('helper.gd', 'Texture2D')"]:
        check(Policy.first_violation(source).is_empty(), "unsupported hint arity defers: " + source)
    check("statically known resource" in Policy.first_violation("load(path)").message, "computed path diagnostic offers a valid literal alternative")
    check("inheritance" not in Policy.first_violation("load('scene.tscn')").message, "structured resource diagnostic recommends preload without inheritance")
    check(not Policy.first_violation("ResourceLoader.\n    load('helper.gd')").is_empty(), "multiline direct singleton receiver remains checked")

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
    for malformed in ["load('helper.gd'", "load('helper.gd", "load([path)", "load('helper.gd', 'Texture2D')", "ResourceLoader.load_threaded_get('helper.gd', 'Texture2D')"]:
        write_text(main, "extends Node\nfunc broken():\n    return " + malformed + "\n")
        rejected = runner.load_game(ws)
        check(not rejected.ok and "failed to compile" in rejected.error and runner.active_game == old_game and old_game.probe() == 12, "Godot rejects malformed call and preserves previous game: " + malformed)
    write_text(main, "extends Node\nconst H = preload('helper.gd')\nfunc probe(): return H.new().value()\n")
    write_text(ws.path_join("nested/uppercase.GD"), "extends RefCounted\nfunc later(): return load('boss.gd')\n")
    rejected = runner.load_game(ws)
    check(not rejected.ok and "uppercase.GD:2:" in rejected.error, "checks uppercase script extensions on Windows")
    write_text(ws.path_join("nested/uppercase.GD"), "extends RefCounted\n")
    write_text(ws.path_join(".git/ignored.gd"), "load('ignored.gd')")
    write_text(ws.path_join(".godot/ignored.gd"), "load('ignored.gd')")
    check(runner.load_game(ws).ok and runner.active_game.probe() == 99, "fixed candidate refreshes helper and ignores metadata directories")
    write_text(main, "extends Node\nconst H = preload('helper.gd')\nvar answer = 0\nfunc _ready():\n    var config = ConfigFile.new()\n    config.set_value('game', 'answer', H.new().value())\n    config.save('%s')\n    var restored = ConfigFile.new()\n    restored.load('%s')\n    answer = restored.get_value('game', 'answer')\n" % [ws.path_join("settings.cfg"), ws.path_join("settings.cfg")])
    check(runner.load_game(ws).ok and runner.active_game.answer == 99, "production reload accepts ConfigFile save/load and restores ordinary file data")
    runner.queue_free()
    await process_frame
    await process_frame
