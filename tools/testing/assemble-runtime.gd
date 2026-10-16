extends SceneTree
const Inventory = preload("res://src/agent/harness_inventory.gd")
func _init() -> void:
    var args = OS.get_cmdline_user_args()
    if args.size() != 2:
        quit(2)
        return
    var result = Inventory.assemble_runtime(args[0], args[1])
    if not result.ok: printerr(result.error)
    quit(0 if result.ok else 1)
