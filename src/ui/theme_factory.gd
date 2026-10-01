class_name ThemeFactory
extends RefCounted

static func build() -> Theme:
    var theme = Theme.new()
    theme.default_font_size = 16
    theme.set_font_size("font_size", "Button", 14)
    theme.set_font_size("font_size", "Label", 15)
    theme.set_font_size("font_size", "LineEdit", 16)
    theme.set_font_size("font_size", "TextEdit", 16)
    theme.set_font_size("font_size", "RichTextLabel", 15)

    var panel = StyleBoxFlat.new()
    panel.bg_color = Color("101522")
    panel.corner_radius_top_left = 14; panel.corner_radius_top_right = 14
    panel.corner_radius_bottom_left = 14; panel.corner_radius_bottom_right = 14
    panel.border_width_left = 1; panel.border_width_top = 1; panel.border_width_right = 1; panel.border_width_bottom = 1
    panel.border_color = Color("273149")
    theme.set_stylebox("panel", "PanelContainer", panel)

    var button = StyleBoxFlat.new()
    button.bg_color = Color("202942")
    button.corner_radius_top_left = 7; button.corner_radius_top_right = 7
    button.corner_radius_bottom_left = 7; button.corner_radius_bottom_right = 7
    button.content_margin_left = 10; button.content_margin_right = 10
    button.content_margin_top = 6; button.content_margin_bottom = 6
    theme.set_stylebox("normal", "Button", button)
    var hover = button.duplicate(); hover.bg_color = Color("2b385a")
    theme.set_stylebox("hover", "Button", hover)
    var pressed = button.duplicate(); pressed.bg_color = Color("182036")
    theme.set_stylebox("pressed", "Button", pressed)

    var input = StyleBoxFlat.new()
    input.bg_color = Color("0b0f19")
    input.corner_radius_top_left = 9; input.corner_radius_top_right = 9
    input.corner_radius_bottom_left = 9; input.corner_radius_bottom_right = 9
    input.border_width_left = 1; input.border_width_top = 1; input.border_width_right = 1; input.border_width_bottom = 1
    input.border_color = Color("2a3550")
    input.content_margin_left = 12; input.content_margin_right = 12
    input.content_margin_top = 10; input.content_margin_bottom = 10
    theme.set_stylebox("normal", "LineEdit", input)
    theme.set_stylebox("normal", "TextEdit", input)
    return theme
