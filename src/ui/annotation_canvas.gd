extends Control

var picture: Image
var texture: ImageTexture
var strokes: Array = []
var pen_color := Color("ff405c")
var pen_width := 6.0
var drawing := false

func set_picture(image: Image, marks: Array = []) -> void:
    picture = image
    texture = ImageTexture.create_from_image(image)
    strokes = marks.duplicate(true)
    drawing = false
    mouse_default_cursor_shape = Control.CURSOR_CROSS
    queue_redraw()

func image_rect() -> Rect2:
    if picture == null: return Rect2()
    var dimensions := Vector2(picture.get_size())
    var scale_factor := minf(size.x / dimensions.x, size.y / dimensions.y)
    return Rect2((size - dimensions * scale_factor) / 2, dimensions * scale_factor)

func picture_point(point: Vector2) -> Vector2:
    var rect := image_rect()
    return ((point - rect.position) / rect.size * Vector2(picture.get_size())).clamp(Vector2.ZERO, Vector2(picture.get_size()) - Vector2.ONE)

func begin_stroke(point: Vector2) -> bool:
    if picture == null or not image_rect().has_point(point): return false
    strokes.append({"points": [picture_point(point)], "color": pen_color, "width": pen_width})
    drawing = true
    queue_redraw()
    return true

func extend_stroke(point: Vector2) -> void:
    if not drawing: return
    strokes.back().points.append(picture_point(point))
    queue_redraw()

func end_stroke() -> void:
    drawing = false

func undo() -> void:
    end_stroke()
    if not strokes.is_empty(): strokes.pop_back()
    queue_redraw()

func clear_marks() -> void:
    end_stroke()
    strokes.clear()
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed: begin_stroke(event.position)
        else: end_stroke()
        accept_event()
    elif event is InputEventMouseMotion and drawing:
        if event.button_mask & MOUSE_BUTTON_MASK_LEFT: extend_stroke(event.position)
        else: end_stroke()
        accept_event()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("0b1014"))
    if texture == null: return
    var rect := image_rect()
    draw_texture_rect(texture, rect, false)
    var scale_factor := rect.size.x / picture.get_width()
    for stroke in strokes:
        var points := PackedVector2Array()
        for point in stroke.points: points.append(rect.position + point * scale_factor)
        var width: float = stroke.width * scale_factor
        if points.size() > 1: draw_polyline(points, stroke.color, width, true)
        for point in [points[0], points[-1]]: draw_circle(point, width / 2, stroke.color, true, -1, true)

func flatten() -> Image:
    var result: Image = picture.duplicate()
    result.convert(Image.FORMAT_RGBA8)
    for stroke in strokes:
        var points: Array = stroke.points
        for i in points.size():
            var a: Vector2 = points[maxi(0, i - 1)]
            var b: Vector2 = points[i]
            var radius: float = stroke.width / 2.0
            # Rasterize the capsule in source pixels, independent of UI scaling.
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
