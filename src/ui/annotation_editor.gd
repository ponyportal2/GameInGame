extends PanelContainer

signal attached(image: Image, original: Image, strokes: Array)
signal cancelled
var canvas = preload("res://src/ui/annotation_canvas.gd").new()
var comment := LineEdit.new()
var voice_status := Label.new()

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var box := VBoxContainer.new()
    add_child(box)
    var bar := HBoxContainer.new()
    box.add_child(bar)
    var title := Label.new()
    title.text = "Mark what you want to change"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(title)
    for color in [Color("ff405c"), Color("ffdf3f"), Color("27dfff"), Color.WHITE, Color.BLACK]:
        var button := Button.new()
        button.text = "●"
        button.add_theme_color_override("font_color", color)
        button.tooltip_text = "Pen: " + color.to_html(false)
        button.pressed.connect(func(): canvas.pen_color = color)
        bar.add_child(button)
    var width := SpinBox.new()
    width.min_value = 2
    width.max_value = 24
    width.value = canvas.pen_width
    width.tooltip_text = "Pen thickness in screenshot pixels"
    width.value_changed.connect(func(value): canvas.pen_width = value)
    bar.add_child(width)
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.resized.connect(canvas.queue_redraw)
    box.add_child(canvas)
    comment.placeholder_text = "Add a picture comment…"
    comment.max_length = 1024
    box.add_child(comment)
    voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(voice_status)
    var actions := HBoxContainer.new()
    box.add_child(actions)
    _button(actions, "Undo", canvas.undo)
    _button(actions, "Clear", canvas.clear_marks)
    var hint := Label.new()
    hint.text = "Draw on the frozen picture.  Esc to cancel"
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    actions.add_child(hint)
    _button(actions, "Cancel", func(): cancelled.emit())
    _button(actions, "Attach picture", attach)
    hide()

func _button(parent: Node, text: String, action: Callable) -> void:
    var button := Button.new()
    button.text = text
    button.pressed.connect(action)
    parent.add_child(button)

func attach() -> void:
    attached.emit(canvas.flatten(), canvas.picture, canvas.strokes.duplicate(true))

func open(image: Image, strokes: Array = [], caption: String = "") -> void:
    canvas.set_picture(image, strokes)
    comment.text = caption
    show()
