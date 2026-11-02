extends SceneTree

var passed := 0
var failed := 0

func _init() -> void:
    call_deferred("run")

func check(value: bool, message: String) -> void:
    if value:
        passed += 1
        print("PASS: ", message)
    else:
        failed += 1
        push_error("FAIL: " + message)

func run() -> void:
    var Canvas = load("res://src/ui/annotation_canvas.gd")
    var Pictures = load("res://src/core/chat_pictures.gd")
    check(Canvas != null and Pictures != null, "annotation canvas and private picture store exist")
    if Canvas == null or Pictures == null:
        quit(1)
        return
    var image := Image.create(200, 100, false, Image.FORMAT_RGBA8)
    image.fill(Color.BLACK)
    var canvas = Canvas.new()
    canvas.size = Vector2(400, 400)
    canvas.set_picture(image)
    check(canvas.image_rect() == Rect2(0, 100, 400, 200), "picture is fitted without stretching")
    check(canvas.picture_point(Vector2(200, 200)) == Vector2(100, 50), "pen coordinates map to original PNG pixels")
    check(not canvas.begin_stroke(Vector2(5, 5)), "letterbox clicks do not draw")
    canvas.pen_color = Color.RED
    canvas.pen_width = 8
    check(canvas.begin_stroke(Vector2(40, 200)), "drawing starts inside the picture")
    canvas.extend_stroke(Vector2(360, 200))
    canvas.end_stroke()
    var marked: Image = canvas.flatten()
    check(marked.get_size() == image.get_size(), "flattening preserves screenshot dimensions")
    check(marked.get_pixel(100, 50).r > 0.9, "PNG contains pen marks at original image coordinates")
    check(image.get_pixel(100, 50) == Color.BLACK, "drawing leaves the original screenshot unchanged")
    check(marked.get_pixel(100, 20) == Color.BLACK, "pen does not alter unrelated pixels")
    canvas.undo()
    check(canvas.flatten().get_pixel(100, 50) == Color.BLACK, "undo removes a complete stroke")
    canvas.begin_stroke(Vector2(200, 200))
    canvas.end_stroke()
    check(canvas.flatten().get_pixel(100, 50).r > 0.9, "single click produces a pen dot")
    canvas.clear_marks()
    check(canvas.strokes.is_empty(), "clear removes all markings")
    var pictures = Pictures.new()
    pictures.game_name = "Picture regression"
    var saved: Dictionary = pictures.save_picture(marked)
    check(saved.get("ok", false), "marked picture is saved as a private PNG")
    var read: Dictionary = pictures.inspect_picture(saved.get("id", ""))
    check(read.get("ok", false) and read.get("mime_type") == "image/png", "agent can open a saved PNG by attachment identity")
    var decoded := Image.new()
    check(decoded.load_png_from_buffer(Marshalls.base64_to_raw(read.get("image_base64", ""))) == OK and decoded.get_pixel(100, 50).r > 0.9, "tool returns the actual marked PNG")
    for id in ["../other.png", "", "/tmp/outside", "wrong.png"]:
        check(not pictures.inspect_picture(id).get("ok", false), "invalid or absent attachment identity is rejected: " + id)
    var other = Pictures.new()
    other.game_name = "Other game"
    check(not other.inspect_picture(saved.id).get("ok", false), "attachment access is confined to the current game")
    var tools = load("res://src/core/game_tools.gd").new()
    tools.picture_store = pictures
    var bridge := "user://picture-bridge"
    DirAccess.make_dir_recursive_absolute(bridge)
    for harness in preload("res://src/agent/harness_inventory.gd").all():
        var controller = load("res://" + harness.controller).new()
        root.add_child(controller)
        controller.tools = tools
        controller._dispatch_host_request({"id": "picture", "command": "inspect_attachment", "args": {"id": saved.id}}, bridge)
        var response = JSON.parse_string(FileAccess.get_file_as_string(bridge.path_join("response-picture.json")))
        check(response is Dictionary and response.get("image_base64") == read.image_base64, harness.id + " bridge returns the real marked PNG")
        controller.queue_free()
    await process_frame
    var history = load("res://src/core/chat_history.gd").new()
    history.seed(pictures.game_name, [])
    history.append(pictures.game_name, {"type": "message", "role": "user", "content": "Fix this", "pictures": [{"id": saved.id, "caption": "red line"}]})
    var events: Array = history.read_all(pictures.game_name)
    check(events.back().pictures[0].id == saved.id and events.back().pictures[0].caption == "red line", "chat replay retains image identity and caption")
    var transcript = load("res://src/core/transcript_store.gd").new()
    transcript.append("Picture seeded", "user", "internal inspect_attachment", {"content": "Visible text", "pictures": [{"id": saved.id, "caption": "Keep caption"}]})
    history.seed("Picture seeded", transcript.read_all("Picture seeded"))
    var seeded: Dictionary = history.read_all("Picture seeded").back()
    check(seeded.content == "Visible text" and seeded.pictures[0].caption == "Keep caption", "transcript fallback restores pictures without exposing internal instructions")
    var metadata = load("res://src/core/metadata_store.gd").new()
    check(metadata.rename_game(pictures.game_name, "Renamed pictures"), "game metadata can be renamed with its saved pictures")
    pictures.game_name = "Renamed pictures"
    check(pictures.inspect_picture(saved.id).ok and history.read_all(pictures.game_name).back().pictures[0].id == saved.id, "relative attachment identity and history survive a workspace rename")
    check(metadata.delete_game(pictures.game_name) and not pictures.inspect_picture(saved.id).ok, "deleting game metadata also deletes its pictures")
    canvas.free()
    print("Chat picture assertions: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
