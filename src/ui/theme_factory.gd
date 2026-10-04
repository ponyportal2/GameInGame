class_name ThemeFactory
extends RefCounted

const BACKGROUND = Color("101416")
const SURFACE = Color("191e21")
const BORDER = Color("30383d")
const TEXT = Color("eef2ef")
const MUTED = Color("97a6ab")
const ACCENT = Color("b8e986")

static func box(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT, padding: int = 14) -> StyleBoxFlat:
    var style = StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(radius)
    style.set_border_width_all(1)
    style.border_color = border
    style.content_margin_left = padding
    style.content_margin_right = padding
    style.content_margin_top = 10
    style.content_margin_bottom = 10
    return style

static func build() -> Theme:
    var theme = Theme.new()
    var font = SystemFont.new()
    font.font_names = PackedStringArray(["Inter", "Segoe UI", "Noto Sans", "DejaVu Sans"])
    theme.default_font = font
    theme.default_font_size = 15
    for type in ["Label", "Button", "LineEdit", "TextEdit", "RichTextLabel", "OptionButton"]:
        theme.set_color("font_color", type, TEXT)
        theme.set_font_size("font_size", type, 15)
    theme.set_font_size("normal_font_size", "RichTextLabel", 16)
    theme.set_constant("line_separation", "RichTextLabel", 5)
    theme.set_constant("separation", "VBoxContainer", 12)
    theme.set_constant("separation", "HBoxContainer", 10)
    theme.set_stylebox("panel", "PanelContainer", box(SURFACE, 12, BORDER))
    theme.set_stylebox("panel", "PopupMenu", box(SURFACE, 8, BORDER))
    theme.set_color("font_color", "PopupMenu", TEXT)
    theme.set_color("font_hover_color", "PopupMenu", ACCENT)
    theme.set_constant("v_separation", "PopupMenu", 12)
    theme.set_stylebox("panel", "Window", box(SURFACE, 12, BORDER))
    for type in ["Button", "OptionButton"]:
        theme.set_stylebox("normal", type, box(Color("2a3237"), 8, BORDER))
        theme.set_stylebox("hover", type, box(Color("364148"), 8, Color("536269")))
        theme.set_stylebox("pressed", type, box(Color("20282c"), 8, ACCENT))
        theme.set_stylebox("disabled", type, box(Color("202629"), 8, Color("293136")))
        theme.set_stylebox("focus", type, box(Color.TRANSPARENT, 8, ACCENT, 0))
        theme.set_color("font_disabled_color", type, Color("637178"))
        theme.set_color("font_hover_color", type, TEXT)
        theme.set_color("font_pressed_color", type, TEXT)
    theme.set_type_variation("PrimaryButton", "Button")
    theme.set_stylebox("normal", "PrimaryButton", box(ACCENT, 8))
    theme.set_stylebox("hover", "PrimaryButton", box(Color("ccf5a5"), 8))
    theme.set_stylebox("pressed", "PrimaryButton", box(Color("9fce6d"), 8))
    for state in ["font_color", "font_hover_color", "font_pressed_color"]:
        theme.set_color(state, "PrimaryButton", Color("162014"))
    theme.set_type_variation("QuietButton", "Button")
    theme.set_stylebox("normal", "QuietButton", box(Color.TRANSPARENT, 8))
    theme.set_stylebox("disabled", "QuietButton", box(Color.TRANSPARENT, 8))
    theme.set_type_variation("DangerButton", "Button")
    theme.set_color("font_color", "DangerButton", Color("f0a69a"))
    for type in ["LineEdit", "TextEdit"]:
        theme.set_stylebox("normal", type, box(Color("111719"), 8, BORDER))
        theme.set_stylebox("read_only", type, box(Color("171d20"), 8, BORDER))
        theme.set_stylebox("focus", type, box(Color.TRANSPARENT, 8, Color("86b365"), 0))
        theme.set_color("font_placeholder_color", type, Color("708087"))
        theme.set_color("caret_color", type, ACCENT)
        theme.set_color("selection_color", type, Color("3c5540"))
    theme.set_stylebox("scroll", "VScrollBar", box(Color("161c1f"), 4, Color.TRANSPARENT, 3))
    theme.set_stylebox("grabber", "VScrollBar", box(Color("435057"), 4, Color.TRANSPARENT, 3))
    theme.set_stylebox("grabber_highlight", "VScrollBar", box(Color("61747c"), 4, Color.TRANSPARENT, 3))
    var separator = StyleBoxLine.new()
    separator.color = BORDER
    separator.thickness = 1
    theme.set_stylebox("separator", "HSeparator", separator)
    theme.set_stylebox("panel", "TabContainer", box(SURFACE, 8, BORDER, 20))
    theme.set_stylebox("tab_selected", "TabContainer", box(Color("303d32"), 6))
    theme.set_stylebox("tab_unselected", "TabContainer", box(Color("20282c"), 6))
    theme.set_color("font_selected_color", "TabContainer", ACCENT)
    theme.set_color("font_unselected_color", "TabContainer", MUTED)
    return theme
