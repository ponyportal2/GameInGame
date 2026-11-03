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

func reference_flatten(image: Image, strokes: Array) -> Image:
    # Original bounding-rectangle rasterizer: a small pixel-for-pixel oracle.
    var result: Image = image.duplicate()
    result.convert(Image.FORMAT_RGBA8)
    for stroke in strokes:
        var points: Array = stroke.points
        for i in points.size():
            var a: Vector2 = points[maxi(0, i - 1)]
            var b: Vector2 = points[i]
            var radius: float = stroke.width / 2.0
            for y in range(maxi(0, int(minf(a.y, b.y) - radius)), mini(result.get_height(), ceili(maxf(a.y, b.y) + radius) + 1)):
                for x in range(maxi(0, int(minf(a.x, b.x) - radius)), mini(result.get_width(), ceili(maxf(a.x, b.x) + radius) + 1)):
                    var p := Vector2(x, y)
                    var nearest := a
                    if a != b: nearest = a + (b - a) * clampf((p - a).dot(b - a) / a.distance_squared_to(b), 0, 1)
                    var coverage := clampf(radius + 0.5 - p.distance_to(nearest), 0, 1)
                    if coverage > 0:
                        var color: Color = stroke.color
                        color.a *= coverage
                        result.set_pixel(x, y, result.get_pixel(x, y).blend(color))
    return result

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
    for delta in [Vector2(65, 40), Vector2(-65, 40), Vector2(65, -40), Vector2(-65, -40), Vector2(0, 40), Vector2(65, 0), Vector2.ZERO, Vector2(65, 0.2), Vector2(0.2, 40)]:
        var sample := Image.create(80, 60, false, Image.FORMAT_RGBA8)
        sample.fill(Color(0.1, 0.2, 0.3, 0.5))
        for width in [2.0, 7.5, 24.0]:
            var marks := [{"points": [Vector2(40.25, 30.75) - delta / 2, Vector2(40.25, 30.75) + delta / 2], "color": Color(1, 0.2, 0.4, 0.6), "width": width}]
            canvas.set_picture(sample, marks)
            check(canvas.flatten().get_data() == reference_flatten(sample, marks).get_data(), "flattening matches original pixels: delta=%s width=%s" % [delta, width])
    var pictures = Pictures.new()
    pictures.game_name = "Picture regression"
    var saved: Dictionary = pictures.save_picture(marked)
    check(saved.get("ok", false), "marked picture is saved as a private PNG")
    check(pictures.has_method("has_picture"), "picture availability can be checked without image transport")
    if pictures.has_method("has_picture"):
        check(pictures.has_picture(saved.id), "saved attachment passes lightweight availability check")
        check(not pictures.has_picture("../other.png") and not pictures.has_picture("f".repeat(32)), "availability check rejects invalid and missing IDs")
        var oversized_id := "e".repeat(32)
        var oversized := FileAccess.open(pictures._path(oversized_id), FileAccess.WRITE)
        oversized.resize(pictures.MAX_PNG_BYTES + 1)
        oversized.close()
        check(not pictures.has_picture(oversized_id), "availability check rejects oversized files")
        pictures.remove_draft(oversized_id)
    var read: Dictionary = pictures.inspect_picture(saved.get("id", ""))
    check(read.get("ok", false) and read.get("mime_type") == "image/png", "agent can open a saved PNG by attachment identity")
    var decoded := Image.new()
    check(decoded.load_png_from_buffer(Marshalls.base64_to_raw(read.get("image_base64", ""))) == OK and decoded.get_pixel(100, 50).r > 0.9, "tool returns the actual marked PNG")
    for id in ["../other.png", "", "/tmp/outside", "wrong.png"]:
        check(not pictures.inspect_picture(id).get("ok", false), "invalid or absent attachment identity is rejected: " + id)
        check(pictures.picture_image(id) == null, "preview decoding rejects invalid attachment identity: " + id)
    var other = Pictures.new()
    other.game_name = "Other game"
    check(not other.inspect_picture(saved.id).get("ok", false), "attachment access is confined to the current game")
    check(other.picture_image(saved.id) == null, "preview decoding preserves per-game isolation")
    if other.has_method("has_picture"):
        check(not other.has_picture(saved.id), "availability check preserves per-game isolation")
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
    for dimensions in [Vector2i(2560, 1440), Vector2i(3840, 2160)]:
        var large := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
        large.fill(Color.BLACK)
        canvas.set_picture(large, [{"points": [Vector2(20, 20), Vector2(dimensions - Vector2i(20, 20))], "color": Color.RED, "width": 8.0}])
        var started := Time.get_ticks_usec()
        var diagonal: Image = canvas.flatten()
        print("Sparse diagonal ", dimensions, ": ", (Time.get_ticks_usec() - started) / 1000.0, " ms")
        check(diagonal.get_pixel(dimensions.x / 2, dimensions.y / 2).r > 0.9 and diagonal.get_pixel(20, dimensions.y - 20) == Color.BLACK, "sparse diagonal marks its center and preserves distant pixels")
    canvas.free()
    print("Chat picture assertions: ", passed, " passed, ", failed, " failed")
    quit(1 if failed else 0)
