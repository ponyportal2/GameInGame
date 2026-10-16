extends SceneTree
const Inventory = preload("res://src/agent/harness_inventory.gd")
func _init() -> void:
    var ids: Array = []
    for harness in Inventory.all():
        assert(not harness.id in ids)
        ids.append(harness.id)
        var directory = "user://assembled/" + str(harness.id)
        var result = Inventory.assemble_runtime(harness.id, directory)
        if not result.ok:
            push_error("FAIL: " + str(result.error))
            quit(1)
            return
        for pair in harness.modules:
            if FileAccess.get_file_as_bytes(directory.path_join(pair[0])) != FileAccess.get_file_as_bytes("res://tools/" + str(pair[1])):
                push_error("FAIL: runtime bytes differ " + str(harness.id) + "/" + str(pair[0]))
                quit(1)
                return
        print("PASS: canonical runtime assembled " + str(harness.id))
    if ids.size() != 14 or Inventory.assemble_runtime("unknown", "user://unknown").ok:
        push_error("FAIL: inventory coverage/unknown harness")
        quit(1)
        return
    quit(0)
