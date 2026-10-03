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
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("Cannot write fixture: " + path)
        return
    f.store_string(text)
    f.close()

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
    var path = "user://cache-regression/" + name
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
    await test_direct_dependency_refresh()
    await test_repeated_dependency_refresh()
    await test_nested_preload_refresh()
    await test_shared_dependency_refresh()
    await test_failed_dependency_restores_cache_behavior()
    await test_new_uncached_broken_draft_is_ignored()
    await test_removed_dependency_does_not_block_reload()
    await test_former_dependency_left_on_disk_does_not_block_reload()
    print("CACHE REGRESSION TESTS: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)

func test_direct_dependency_refresh() -> void:
    var ws = fresh_workspace("direct")
    var helper = ws.path_join("helper.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 41\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var H = load('%s')\n    answer = H.new().value()\n" % helper)
    var runner = new_runner()
    var first = runner.load_game(ws)
    check(first.ok and runner.active_game.answer == 41, "direct load uses initial helper source")
    write_text(helper, "extends RefCounted\nfunc value(): return 99\n")
    var second = runner.load_game(ws)
    check(second.ok and runner.active_game.answer == 99, "direct load sees helper edit without restarting GameSmith")
    await dispose_runner(runner)
    remove_tree(ws)

func test_repeated_dependency_refresh() -> void:
    var ws = fresh_workspace("repeated")
    var helper = ws.path_join("helper.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 0\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = -1\nfunc _ready():\n    var H = load('%s')\n    answer = H.new().value()\n" % helper)
    var runner = new_runner()
    var all_fresh = true
    for expected in range(25):
        write_text(helper, "extends RefCounted\nfunc value(): return %d\n" % expected)
        var result = runner.load_game(ws)
        if not result.ok or runner.active_game.answer != expected:
            all_fresh = false
            break
    check(all_fresh, "25 consecutive helper-only edits always run current source")
    await dispose_runner(runner)
    remove_tree(ws)

func test_nested_preload_refresh() -> void:
    var ws = fresh_workspace("nested")
    var leaf = ws.path_join("leaf.gd")
    var middle = ws.path_join("middle.gd")
    write_text(leaf, "extends RefCounted\nfunc value(): return 40\n")
    write_text(middle, "extends RefCounted\nconst Leaf = preload('leaf.gd')\nfunc value(): return Leaf.new().value() + 1\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var Middle = load('%s')\n    answer = Middle.new().value()\n" % middle)
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 41, "nested preload chain uses initial leaf")
    write_text(leaf, "extends RefCounted\nfunc value(): return 98\n")
    check(runner.load_game(ws).ok and runner.active_game.answer == 99, "nested preload chain sees leaf-only edit")
    await dispose_runner(runner)
    remove_tree(ws)

func test_shared_dependency_refresh() -> void:
    var ws = fresh_workspace("shared")
    var shared = ws.path_join("shared.gd")
    var left = ws.path_join("left.gd")
    var right = ws.path_join("right.gd")
    write_text(shared, "extends RefCounted\nfunc value(): return 5\n")
    write_text(left, "extends RefCounted\nconst Shared = preload('%s')\nfunc value(): return Shared.new().value()\n" % shared)
    write_text(right, "extends RefCounted\nconst Shared = preload('%s')\nfunc value(): return Shared.new().value() * 10\n" % shared)
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var L = load('%s')\n    var R = load('%s')\n    answer = L.new().value() + R.new().value()\n" % [left, right])
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 55, "two cached parents share initial dependency")
    write_text(shared, "extends RefCounted\nfunc value(): return 7\n")
    check(runner.load_game(ws).ok and runner.active_game.answer == 77, "two cached parents both see shared dependency edit")
    await dispose_runner(runner)
    remove_tree(ws)

func test_failed_dependency_restores_cache_behavior() -> void:
    var ws = fresh_workspace("rollback")
    var helper = ws.path_join("helper.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 12\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc probe():\n    var H = load('%s')\n    return H.new().value()\nfunc _ready(): answer = probe()\n" % helper)
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 12, "rollback fixture starts from working dependency")
    var old_game = runner.active_game
    write_text(helper, "extends RefCounted\nfunc broken(:\n")
    var rejected = runner.load_game(ws)
    check(not rejected.ok and runner.active_game == old_game, "broken cached dependency rejects candidate and preserves old node")
    check(old_game.probe() == 12, "failed dependency reload restores old cache for subsequent load() calls")
    await dispose_runner(runner)
    remove_tree(ws)

func test_new_uncached_broken_draft_is_ignored() -> void:
    var ws = fresh_workspace("new-unused-draft")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 21\n")
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 21, "uncached-draft fixture starts cleanly")
    write_text(ws.path_join("unused_draft.gd"), "extends RefCounted\nfunc broken(:\n")
    var result = runner.load_game(ws)
    check(result.ok and runner.active_game.answer == 21, "new broken script that was never referenced does not block reload")
    await dispose_runner(runner)
    remove_tree(ws)

func test_removed_dependency_does_not_block_reload() -> void:
    var ws = fresh_workspace("removed")
    var helper = ws.path_join("helper.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 3\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var H = load('%s')\n    answer = H.new().value()\n" % helper)
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 3, "removed-dependency fixture caches helper")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 77\n")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(helper))
    var result = runner.load_game(ws)
    check(result.ok and runner.active_game.answer == 77, "deleting a formerly used helper does not poison later reload")
    await dispose_runner(runner)
    remove_tree(ws)

func test_former_dependency_left_on_disk_does_not_block_reload() -> void:
    var ws = fresh_workspace("unused-broken")
    var helper = ws.path_join("helper.gd")
    write_text(helper, "extends RefCounted\nfunc value(): return 3\n")
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 0\nfunc _ready():\n    var H = load('%s')\n    answer = H.new().value()\n" % helper)
    var runner = new_runner()
    check(runner.load_game(ws).ok and runner.active_game.answer == 3, "unused-dependency fixture first caches helper")
    # Historical RED regression: the eager replacement implementation compiled this
    # abandoned helper even though the new candidate no longer referenced it.
    write_text(ws.path_join("main.gd"), "extends Node\nvar answer = 88\n")
    write_text(helper, "extends RefCounted\nfunc broken(:\n")
    var result = runner.load_game(ws)
    check(result.ok and runner.active_game.answer == 88, "formerly used but now-unreferenced broken helper does not reject valid reload")
    await dispose_runner(runner)
    remove_tree(ws)
