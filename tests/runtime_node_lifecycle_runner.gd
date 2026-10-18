extends SceneTree

class Probe extends Node:
    var events: Array = []
    var enters := 0
    var readies := 0
    var exits := 0
    var processes := 0
    var physics_ticks := 0
    var deferred_calls := 0
    var cached_children: Array = []

    func _enter_tree() -> void:
        enters += 1
        events.append(str(name) + ":enter")

    func _ready() -> void:
        readies += 1
        cached_children = get_children()
        events.append(str(name) + ":ready")
        call_deferred("finish_initialization")

    func finish_initialization() -> void:
        deferred_calls += 1

    func _process(_delta: float) -> void:
        processes += 1

    func _physics_process(_delta: float) -> void:
        physics_ticks += 1
        events.append(str(name) + ":physics")

    func _exit_tree() -> void:
        exits += 1

var passed := 0
var failed := 0

func _init() -> void:
    call_deferred("run")

func check(condition: bool, label: String) -> void:
    if condition:
        passed += 1
        print("PASS: " + label)
    else:
        failed += 1
        push_error("FAIL: " + label)

func probe(label: String, events: Array) -> Probe:
    var node := Probe.new()
    node.name = label
    node.events = events
    return node

func run() -> void:
    var events: Array = []
    var parent := probe("Player", events)
    var early := probe("Early", events)
    parent.add_child(early)
    check(parent.enters == 0 and early.readies == 0, "detached construction does not fire tree lifecycle")
    root.add_child(parent)
    check(events == ["Player:enter", "Early:enter", "Early:ready", "Player:ready"], "initial construction enters parent first and readies child first")
    check(parent.cached_children == [early], "parent ready discovers initial children")

    events.clear()
    var late := probe("Late", events)
    var nested := probe("Nested", events)
    late.add_child(nested)
    parent.add_child(late)
    check(events == ["Late:enter", "Nested:enter", "Nested:ready", "Late:ready"], "late subtree receives synchronous enter and ready callbacks")
    check(parent.readies == 1 and parent.cached_children == [early], "late insertion does not rerun parent ready or refresh its child cache")
    check(late.get_parent() == parent and late.is_node_ready() and nested.is_node_ready(), "late subtree has correct parent and ready state before add_child returns")
    await process_frame
    await process_frame
    for tick in range(3):
        await physics_frame
    await process_frame
    check(late.processes > 0 and nested.processes > 0, "late subtree receives process callbacks")
    check(late.physics_ticks > 0 and nested.physics_ticks > 0, "late subtree receives physics callbacks")
    check(late.deferred_calls == 1 and nested.deferred_calls == 1, "late ready deferred initialization executes")
    var parent_tick := events.find("Player:physics")
    var late_tick := events.find("Late:physics")
    check(parent_tick >= 0 and late_tick > parent_tick, "equal-priority parent physics executes before late child")
    events.clear()
    late.process_physics_priority = -1
    await physics_frame
    await process_frame
    parent_tick = events.find("Player:physics")
    late_tick = events.find("Late:physics")
    check(late_tick >= 0 and parent_tick > late_tick, "explicit physics priority can run late child before parent")

    parent.remove_child(late)
    check(late.exits == 1 and nested.exits == 1, "removing subtree delivers exit callbacks")
    parent.add_child(late)
    check(late.enters == 2 and nested.enters == 2 and late.readies == 1 and nested.readies == 1, "reinsertion enters again but does not repeat ready")
    parent.remove_child(late)
    late.request_ready()
    parent.add_child(late)
    check(late.readies == 2 and nested.readies == 1 and parent.readies == 1, "request_ready affects only requested node on next insertion")

    var disabled := probe("Disabled", events)
    disabled.process_mode = Node.PROCESS_MODE_DISABLED
    parent.add_child(disabled)
    var inherited := probe("Inherited", events)
    disabled.add_child(inherited)
    await process_frame
    await physics_frame
    await process_frame
    check(inherited.readies == 1 and inherited.enters == 1, "disabled parent still allows late child enter and ready")
    check(inherited.processes == 0 and inherited.physics_ticks == 0, "late child inherits disabled processing")
    disabled.process_mode = Node.PROCESS_MODE_INHERIT
    await process_frame
    await physics_frame
    await process_frame
    check(inherited.processes > 0 and inherited.physics_ticks > 0 and inherited.readies == 1, "reenabling processing starts callbacks without rerunning ready")
    parent.free()
    print("Late node lifecycle: %d passed, %d failed (Godot %s)" % [passed, failed, Engine.get_version_info().string])
    quit(1 if failed else 0)
