extends SceneTree

const Runner = preload("res://src/core/game_runner.gd")

var passed := 0
var failed := 0

func _init() -> void:
    call_deferred("run")

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS: ", label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func write_text(path: String, text: String) -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Cannot write fixture: " + path)
        return
    file.store_string(text)
    file.close()

func remove_tree(path: String) -> void:
    var abs = ProjectSettings.globalize_path(path)
    if not DirAccess.dir_exists_absolute(abs):
        return
    var dir = DirAccess.open(abs)
    if dir == null:
        return
    dir.list_dir_begin()
    var name = dir.get_next()
    while name != "":
        if name not in [".", ".."]:
            var child = abs.path_join(name)
            if dir.current_is_dir() and not dir.current_is_link():
                remove_tree(child)
            else:
                DirAccess.remove_absolute(child)
        name = dir.get_next()
    dir.list_dir_end()
    DirAccess.remove_absolute(abs)

func fresh_workspace(name: String) -> String:
    var path = "user://cache-edge-regression/" + name
    remove_tree(path)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
    return path

func new_runner() -> GameRunner:
    var runner = Runner.new()
    root.add_child(runner)
    return runner

func dispose_runner(runner: GameRunner) -> void:
    runner.queue_free()
    await process_frame
    await process_frame

func run() -> void:
    await test_never_loaded_dynamic_dependency_after_rejection()
    await test_extends_chain_refresh_and_rollback()
    await test_rejected_candidate_does_not_pollute_new_dependency_cache()
    print("CACHE EDGE REGRESSIONS: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)

func test_never_loaded_dynamic_dependency_after_rejection() -> void:
    var ws = fresh_workspace("never-loaded-dynamic")
    var helper = ws.path_join("late_helper.gd")
    var main = ws.path_join("main.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 12\n")
    write_text(main, "extends Node\nfunc probe():\n    var H = load('%s')\n    return H.new().value()\n" % helper)
    var runner = new_runner()
    check(runner.load_game(ws).ok, "accepted game can contain a dynamic dependency that has not been loaded yet")
    check(ResourceLoader.get_cached_ref(helper) == null, "late dynamic dependency is not cached before first probe")
    var old_game = runner.active_game

    # RED: the edited helper was never cached by the accepted game, so rollback has
    # no old Resource to restore. The preserved old game must not start executing
    # source that belonged only to the rejected workspace state.
    write_text(helper, "extends RefCounted\nfunc value(): return 99\n")
    write_text(main, "extends Node\nfunc broken(:\n")
    var rejected = runner.load_game(ws)
    check(not rejected.ok and runner.active_game == old_game, "unrelated compile failure preserves the previous active game")
    check(old_game.probe() == 12, "rejected reload preserves never-before-loaded dynamic dependency semantics")

    await dispose_runner(runner)
    remove_tree(ws)

func test_extends_chain_refresh_and_rollback() -> void:
    var ws = fresh_workspace("extends-chain")
    var base = ws.path_join("base.gd")
    var derived = ws.path_join("derived.gd")
    var main = ws.path_join("main.gd")
    write_text(base, "extends RefCounted\nfunc value(): return 10\n")
    write_text(derived, "extends '%s'\nfunc derived_value(): return value() + 1\n" % base)
    write_text(main, "extends Node\nconst D = preload('%s')\nvar answer = D.new().derived_value()\n" % derived)
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 11, "script inheritance chain loads initial base")

    write_text(base, "extends RefCounted\nfunc value(): return 20\n")
    check(runner.load_game(ws).ok and runner.active_game.answer == 21, "script inheritance chain sees base-only edit")
    var old_game = runner.active_game

    write_text(base, "extends RefCounted\nfunc broken(:\n")
    var rejected = runner.load_game(ws)
    check(not rejected.ok and runner.active_game == old_game, "broken inherited base rejects candidate and preserves old game")
    var restored = load(derived)
    check(restored != null and restored.new().derived_value() == 21, "rollback restores inherited script chain for later load()")

    await dispose_runner(runner)
    remove_tree(ws)

func test_rejected_candidate_does_not_pollute_new_dependency_cache() -> void:
    var ws = fresh_workspace("new-dependency-pollution")
    var main = ws.path_join("main.gd")
    var new_dependency = ws.path_join("new_dependency.gd")
    write_text(main, "extends Node\nvar answer = 1\n")
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 1, "new-dependency pollution fixture starts cleanly")

    write_text(new_dependency, "extends RefCounted\nfunc value(): return 77\n")
    write_text(main, "extends Node\nfunc _ready():\n    var H = load('%s')\n    var values = []\n    print(values[123])\n" % new_dependency)
    var rejected = runner.load_game(ws)
    check(not rejected.ok, "candidate that loaded a brand-new dependency can still be rejected during startup")
    check(ResourceLoader.get_cached_ref(new_dependency) == null, "rejected candidate removes its brand-new dependency from ResourceLoader cache")

    await dispose_runner(runner)
    remove_tree(ws)
