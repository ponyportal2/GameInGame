extends RefCounted

const U = preload("res://src/ui/workspace_ui.gd")
const S = preload("res://src/ui/settings_ui.gd")
const T = preload("res://src/ui/theme_factory.gd")

static func build_hud(app) -> void:
    app.voice_hud = Label.new()
    app.voice_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
    app.voice_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    app.voice_hud.max_lines_visible = 5
    app.voice_hud.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    app.voice_hud.add_theme_stylebox_override("normal", T.box(Color("191e21ee"), 8, T.BORDER))
    app.voice_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    app.voice_hud.offset_left = -580
    app.voice_hud.offset_right = -24
    app.voice_hud.offset_top = -150
    app.voice_hud.offset_bottom = -24
    app.play_hud.add_child(app.voice_hud)
    app.voice_hud.visible = false

static func build_composer(app, parent: Control) -> void:
    var box = U.column(parent, 4)
    app.voice_composer = box
    var row = U.row(box)
    app.voice_record_button = U.button(row, "Record voice", app._toggle_voice, "QuietButton")
    app.voice_send_button = U.button(row, "Send voice", app._send_voice, "QuietButton")
    U.button(row, "Clear voice", app._clear_voice, "QuietButton")
    app.voice_status = U.label(box, "Enable voice in Settings → Voice", 12, T.MUTED)
    app.voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    app.voice_draft_edit = TextEdit.new()
    app.voice_draft_edit.placeholder_text = "Voice transcript — edit here, then Send voice"
    app.voice_draft_edit.custom_minimum_size.y = 58
    app.voice_draft_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    box.add_child(app.voice_draft_edit)
    app.voice_draft_edit.text_changed.connect(func(): app.voice.set_draft(app.voice_draft_edit.text))

static func options(parent: Node, title: String, pairs: Array, description: String = "") -> OptionButton:
    var option = OptionButton.new()
    for pair in pairs:
        option.add_item(pair[0])
        option.set_item_metadata(option.item_count - 1, pair[1])
    S.field(parent, title, option, description)
    return option

static func build_settings(app, tabs: TabContainer) -> void:
    var page = S.page(tabs, "Voice")
    var fields: Dictionary = {}
    var enable = CheckBox.new()
    enable.text = "Enable microphone shortcuts"
    page.add_child(enable)
    fields.enabled = enable
    U.paragraph(page, "Local recognition, independent of the coding harness. Recording and sending voice leave gameplay running. No audio is sent to a provider.")
    fields.model = options(page, "Whisper model", [["Tiny · fastest", "tiny"], ["Base · default", "base"], ["Small", "small"], ["Medium", "medium"], ["Large v3", "large-v3"], ["Turbo", "turbo"]], "Multilingual models download on first use into GameSmith user data, never the game or repository. Larger models need more memory/time. CPU/int8 keeps the game's GPU free.")
    fields.language = options(page, "Language", [["Detect automatically", "auto"], ["English", "en"], ["Russian", "ru"]])
    fields.microphone = options(page, "Microphone", [])
    var keys: Array = []
    for code in [KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12]: keys.append([OS.get_keycode_string(code), code])
    fields.record_key = options(page, "Record / stop shortcut", keys, "Shortcuts apply while GameSmith is focused. Escape cancels active recording/transcription. Recordings stop after 60 seconds.")
    fields.send_key = options(page, "Send voice shortcut", keys)
    fields.auto_send = CheckBox.new()
    fields.auto_send.text = "Send automatically after transcription"
    page.add_child(fields.auto_send)
    U.paragraph(page, "Off by default: review the transcript and press Send voice. If the agent is busy, the transcript stays as a draft; it is never sent later automatically.")
    fields.python = LineEdit.new()
    fields.python.placeholder_text = "python"
    S.field(page, "Python executable", fields.python, "For one-time installation. Python 3.11/3.12 recommended. GameSmith creates a private environment; global packages/settings are unchanged.")
    fields.install = U.button(page, "Install local recognition", app._install_voice, "QuietButton")
    fields.install_status = U.paragraph(page, "")
    app.voice_settings = fields

static func select(option: OptionButton, value: Variant) -> void:
    option.select(0)
    for i in option.item_count:
        if option.get_item_metadata(i) == value:
            option.select(i)
            return

static func refresh_microphones(option: OptionButton, saved: String, devices: PackedStringArray) -> void:
    option.clear()
    for device in devices:
        option.add_item(device)
        option.set_item_metadata(option.item_count - 1, device)
    if saved not in devices:
        option.add_item(saved + " (unavailable)")
        option.set_item_metadata(option.item_count - 1, saved)
    select(option, saved)

static func load_settings(app, settings: Dictionary) -> void:
    var fields = app.voice_settings
    fields.enabled.button_pressed = bool(settings.get("voice_enabled", false))
    select(fields.model, str(settings.get("voice_model", "base")))
    select(fields.language, str(settings.get("voice_language", "auto")))
    refresh_microphones(fields.microphone, str(settings.get("voice_microphone", "Default")), AudioServer.get_input_device_list())
    select(fields.record_key, int(settings.get("voice_record_key", KEY_F8)))
    select(fields.send_key, int(settings.get("voice_send_key", KEY_F9)))
    fields.auto_send.button_pressed = bool(settings.get("voice_auto_send", false))
    fields.python.text = str(settings.get("voice_python", "python"))

static func values(app) -> Dictionary:
    var fields = app.voice_settings
    return {
        "voice_enabled":fields.enabled.button_pressed,
        "voice_model":fields.model.get_item_metadata(fields.model.selected),
        "voice_language":fields.language.get_item_metadata(fields.language.selected),
        "voice_microphone":fields.microphone.get_item_metadata(fields.microphone.selected),
        "voice_record_key":fields.record_key.get_item_metadata(fields.record_key.selected),
        "voice_send_key":fields.send_key.get_item_metadata(fields.send_key.selected),
        "voice_auto_send":fields.auto_send.button_pressed,
        "voice_python":fields.python.text.strip_edges() if fields.python.text.strip_edges() != "" else "python"
    }
