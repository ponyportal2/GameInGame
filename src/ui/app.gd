extends Control

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const PiProviderCatalogScript = preload("res://src/pi/pi_provider_catalog.gd")
const ThemeFactoryScript = preload("res://src/ui/theme_factory.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const LegacyDataMigratorScript = preload("res://src/core/legacy_data_migrator.gd")

const HOST_UI_CANVAS_LAYER = 524287

var store = WorkspaceStoreScript.new()
var metadata = MetadataStoreScript.new()
var transcript = TranscriptStoreScript.new()
var runner
var agent
var tools
var current_game = ""
var pending_delete = ""
var rename_target = ""

var host_ui_canvas: CanvasLayer
var host_ui_root: Control
var background: ColorRect
var game_layer: Control
var library_layer: Control
var play_hud: Control
var chat_overlay: Control
var transcript_view: RichTextLabel
var chat_input: TextEdit
var status_label: Label
var game_title_label: Label
var toast_label: Label
var new_game_dialog: Control
var rename_dialog: ConfirmationDialog
var delete_dialog: ConfirmationDialog
var settings_dialog: Control
var name_edit: LineEdit
var rename_edit: LineEdit
var provider_option: OptionButton
var model_edit: LineEdit
var key_edit: LineEdit
var custom_base_edit: LineEdit
var reasoning_option: OptionButton
var agent_steps_spin: SpinBox
var llm_delay_spin: SpinBox
var compaction_auto_spin: SpinBox
var compaction_keep_spin: SpinBox
var compact_now_button: Button
var compaction_status_label: Label
var library_button: Button
var send_button: Button
var game_override_provider: OptionButton
var game_override_model: LineEdit
var gameplay_mouse_mode := Input.MOUSE_MODE_VISIBLE
var generated_input_states: Array = []
var stream_open_kind := ""

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    theme = ThemeFactoryScript.build()
    var migration = LegacyDataMigratorScript.migrate_user_data()
    store.ensure()
    AppLoggerScript.global_event("app.startup", "user_data=%s legacy_source=%s migrated=%d skipped=%d" % [ProjectSettings.globalize_path("user://"), str(migration.get("source_found", false)), int(migration.get("copied", 0)), int(migration.get("skipped", 0))])
    _build_ui()
    _show_library()
    _maybe_capture()

func _process(_delta: float) -> void:
    # Poll global action state because generated games may consume _input() before the host.
    if current_game != "" and Input.is_action_just_pressed("toggle_chat"):
        _set_chat_visible(not chat_overlay.visible)

func _input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    if event.keycode == KEY_ESCAPE and chat_overlay.visible:
        get_viewport().set_input_as_handled()
        _set_chat_visible(false)
        return
    if chat_overlay.visible and chat_input.has_focus() and not event.shift_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
        # Handle this before TextEdit sees it, otherwise Enter inserts a newline.
        get_viewport().set_input_as_handled()
        _send_chat()

func _build_ui() -> void:
    host_ui_canvas = CanvasLayer.new(); host_ui_canvas.layer = HOST_UI_CANVAS_LAYER; add_child(host_ui_canvas)
    host_ui_root = Control.new(); host_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.theme = theme; host_ui_canvas.add_child(host_ui_root)
    background = ColorRect.new(); background.color = Color("090d16"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(background)
    game_layer = Control.new(); game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(game_layer)
    library_layer = Control.new(); library_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(library_layer)
    play_hud = Control.new(); play_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); play_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; host_ui_root.add_child(play_hud)
    chat_overlay = Control.new(); chat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); chat_overlay.visible = false; chat_overlay.process_mode = Node.PROCESS_MODE_ALWAYS; chat_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; host_ui_root.add_child(chat_overlay)
    _build_library()
    _build_play_hud()
    _build_chat()
    _build_dialogs()

func _build_library() -> void:
    var margin = MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 72); margin.add_theme_constant_override("margin_right", 72)
    margin.add_theme_constant_override("margin_top", 54); margin.add_theme_constant_override("margin_bottom", 54)
    library_layer.add_child(margin)
    var root = VBoxContainer.new(); root.add_theme_constant_override("separation", 18); margin.add_child(root)
    var header = HBoxContainer.new(); header.add_theme_constant_override("separation", 8); root.add_child(header)
    var brand = VBoxContainer.new(); brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(brand)
    var title = Label.new(); title.text = "GAMESMITH"; title.add_theme_font_size_override("font_size", 34); title.add_theme_color_override("font_color", Color("f3f6ff")); brand.add_child(title)
    var subtitle = Label.new(); subtitle.text = "Describe a game. Change it while it runs."; subtitle.add_theme_color_override("font_color", Color("93a1bd")); brand.add_child(subtitle)
    var logs_btn = Button.new(); logs_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER; logs_btn.text = "Logs"; logs_btn.tooltip_text = "Open global GameSmith logs"; logs_btn.pressed.connect(_open_global_logs); header.add_child(logs_btn)
    var settings_btn = Button.new(); settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER; settings_btn.text = "Settings"; settings_btn.tooltip_text = "Pi provider, model, and agent limits"; settings_btn.pressed.connect(_open_settings); header.add_child(settings_btn)
    var new_btn = Button.new(); new_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER; new_btn.text = "+ New Game"; new_btn.pressed.connect(_open_new_game); header.add_child(new_btn)
    var divider = HSeparator.new(); root.add_child(divider)
    var section = Label.new(); section.name = "SectionTitle"; section.text = "YOUR GAMES"; section.add_theme_color_override("font_color", Color("7f8eaa")); section.add_theme_font_size_override("font_size", 13); root.add_child(section)
    var scroll = ScrollContainer.new(); scroll.name = "GameScroll"; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(scroll)
    var games = VBoxContainer.new(); games.name = "GamesList"; games.size_flags_horizontal = Control.SIZE_EXPAND_FILL; games.add_theme_constant_override("separation", 10); scroll.add_child(games)

func _build_play_hud() -> void:
    var top = HBoxContainer.new(); top.position = Vector2(18, 16); top.mouse_filter = Control.MOUSE_FILTER_PASS; play_hud.add_child(top)
    game_title_label = Label.new(); game_title_label.text = ""; game_title_label.add_theme_font_size_override("font_size", 18); game_title_label.add_theme_color_override("font_color", Color("eef3ff")); top.add_child(game_title_label)
    var spacer = Control.new(); spacer.custom_minimum_size.x = 12; top.add_child(spacer)
    var chat_btn = Button.new(); chat_btn.text = "Chat  F1"; chat_btn.mouse_filter = Control.MOUSE_FILTER_STOP; chat_btn.pressed.connect(func(): _set_chat_visible(true)); top.add_child(chat_btn)
    toast_label = Label.new(); toast_label.position = Vector2(20, 665); toast_label.add_theme_color_override("font_color", Color("a6b6d4")); play_hud.add_child(toast_label)

func _build_chat() -> void:
    var shade = ColorRect.new(); shade.color = Color(0.02, 0.025, 0.04, 0.82); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); chat_overlay.add_child(shade)
    var panel = PanelContainer.new(); panel.anchor_left = 0.42; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0; panel.offset_left = 0; panel.offset_top = 0; panel.offset_right = 0; panel.offset_bottom = 0; chat_overlay.add_child(panel)
    var margin = MarginContainer.new(); margin.add_theme_constant_override("margin_left", 24); margin.add_theme_constant_override("margin_right", 24); margin.add_theme_constant_override("margin_top", 22); margin.add_theme_constant_override("margin_bottom", 20); panel.add_child(margin)
    var box = VBoxContainer.new(); box.add_theme_constant_override("separation", 14); margin.add_child(box)
    var head = HBoxContainer.new(); head.add_theme_constant_override("separation", 6); box.add_child(head)
    library_button = Button.new(); library_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER; library_button.text = "← Library"; library_button.tooltip_text = "Unavailable while the agent is working"; library_button.pressed.connect(_return_to_library); head.add_child(library_button)
    var spacer = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(spacer)
    var folder = Button.new(); folder.size_flags_vertical = Control.SIZE_SHRINK_CENTER; folder.text = "Folder"; folder.tooltip_text = "Open generated game workspace"; folder.pressed.connect(_open_folder); head.add_child(folder)
    var logs = Button.new(); logs.size_flags_vertical = Control.SIZE_SHRINK_CENTER; logs.text = "Logs"; logs.tooltip_text = "Open this game's host debug logs"; logs.pressed.connect(_open_game_logs); head.add_child(logs)
    var game_settings = Button.new(); game_settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER; game_settings.text = "Settings"; game_settings.pressed.connect(_open_settings); head.add_child(game_settings)
    var rename = Button.new(); rename.size_flags_vertical = Control.SIZE_SHRINK_CENTER; rename.text = "Rename"; rename.pressed.connect(_open_rename); head.add_child(rename)
    var close = Button.new(); close.size_flags_vertical = Control.SIZE_SHRINK_CENTER; close.text = "Close  Esc"; close.pressed.connect(func(): _set_chat_visible(false)); head.add_child(close)
    status_label = Label.new(); status_label.text = "Ready"; status_label.add_theme_color_override("font_color", Color("8393b2")); box.add_child(status_label)
    transcript_view = RichTextLabel.new(); transcript_view.bbcode_enabled = true; transcript_view.fit_content = false; transcript_view.scroll_active = true; transcript_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; transcript_view.custom_minimum_size.y = 350; box.add_child(transcript_view)
    var composer = HBoxContainer.new(); composer.add_theme_constant_override("separation", 10); box.add_child(composer)
    chat_input = TextEdit.new(); chat_input.placeholder_text = "Describe what to build or change…  Enter sends · Shift+Enter adds a line"; chat_input.custom_minimum_size.y = 64; chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; chat_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; composer.add_child(chat_input)
    send_button = Button.new(); send_button.text = "Send"; send_button.custom_minimum_size = Vector2(82, 64); send_button.pressed.connect(_send_chat); composer.add_child(send_button)

func _build_dialogs() -> void:
    _build_new_game_overlay()
    rename_dialog = ConfirmationDialog.new(); rename_dialog.title = "Rename game"; add_child(rename_dialog)
    rename_edit = LineEdit.new(); rename_edit.custom_minimum_size.x = 360; rename_dialog.add_child(rename_edit); rename_edit.position = Vector2(24, 58); rename_dialog.confirmed.connect(_rename_game)
    delete_dialog = ConfirmationDialog.new(); delete_dialog.title = "Delete game"; delete_dialog.confirmed.connect(_delete_game_confirmed); add_child(delete_dialog)
    _build_settings_overlay()

func _build_new_game_overlay() -> void:
    new_game_dialog = Control.new()
    new_game_dialog.name = "NewGameOverlay"
    new_game_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    new_game_dialog.visible = false
    new_game_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
    new_game_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
    host_ui_root.add_child(new_game_dialog)

    var shade = ColorRect.new()
    shade.color = Color(0.015, 0.02, 0.03, 0.88)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    new_game_dialog.add_child(shade)

    var center = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    new_game_dialog.add_child(center)

    var panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(460, 190)
    center.add_child(panel)

    var margin = MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 22)
    margin.add_theme_constant_override("margin_right", 22)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_bottom", 18)
    panel.add_child(margin)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    margin.add_child(box)

    var title = Label.new()
    title.text = "Create a game"
    title.add_theme_font_size_override("font_size", 22)
    box.add_child(title)

    var note = Label.new()
    note.text = "Name your game. The workspace starts empty with a baseline Git commit."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_color_override("font_color", Color("8492ad"))
    box.add_child(note)

    name_edit = LineEdit.new()
    name_edit.placeholder_text = "Neon Asteroids"
    box.add_child(name_edit)
    name_edit.text_submitted.connect(func(_text): _create_game())

    var actions = HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_END
    actions.add_theme_constant_override("separation", 8)
    box.add_child(actions)

    var cancel = Button.new()
    cancel.text = "Cancel"
    cancel.pressed.connect(func(): new_game_dialog.visible = false)
    actions.add_child(cancel)

    var create = Button.new()
    create.text = "Create"
    create.pressed.connect(_create_game)
    actions.add_child(create)

func _open_new_game() -> void:
    name_edit.text = ""
    new_game_dialog.visible = true
    name_edit.grab_focus()

func _build_settings_overlay() -> void:
    settings_dialog = Control.new()
    settings_dialog.name = "SettingsOverlay"
    settings_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    settings_dialog.visible = false
    settings_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
    settings_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
    host_ui_root.add_child(settings_dialog)

    var shade = ColorRect.new()
    shade.color = Color(0.015, 0.02, 0.03, 0.90)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    settings_dialog.add_child(shade)

    var center = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    settings_dialog.add_child(center)

    var panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(620, 610)
    center.add_child(panel)

    var outer = MarginContainer.new()
    outer.add_theme_constant_override("margin_left", 20)
    outer.add_theme_constant_override("margin_right", 20)
    outer.add_theme_constant_override("margin_top", 16)
    outer.add_theme_constant_override("margin_bottom", 16)
    panel.add_child(outer)

    var root_box = VBoxContainer.new()
    root_box.add_theme_constant_override("separation", 10)
    outer.add_child(root_box)

    var head = HBoxContainer.new()
    root_box.add_child(head)
    var title = Label.new()
    title.text = "Settings"
    title.add_theme_font_size_override("font_size", 22)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    var close_btn = Button.new()
    close_btn.text = "Close"
    close_btn.pressed.connect(_close_settings)
    head.add_child(close_btn)

    var settings_scroll = ScrollContainer.new()
    settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root_box.add_child(settings_scroll)
    var sm = MarginContainer.new()
    sm.add_theme_constant_override("margin_right", 10)
    settings_scroll.add_child(sm)
    var sv = VBoxContainer.new()
    sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sv.add_theme_constant_override("separation", 8)
    sm.add_child(sv)

    sv.add_child(_small_label("Pi turn limit per request"))
    agent_steps_spin = SpinBox.new()
    agent_steps_spin.min_value = PiAgentControllerScript.MIN_AGENT_STEPS
    agent_steps_spin.max_value = PiAgentControllerScript.MAX_AGENT_STEPS
    agent_steps_spin.step = 1
    agent_steps_spin.allow_greater = false
    agent_steps_spin.allow_lesser = false
    agent_steps_spin.tooltip_text = "Maximum Pi agent turns before GameSmith stops a runaway request."
    sv.add_child(agent_steps_spin)
    var agent_note = Label.new()
    agent_note.text = "Default: 150. Lower it to cap cost/latency; raise it for larger builds."
    agent_note.add_theme_color_override("font_color", Color("8492ad"))
    sv.add_child(agent_note)

    sv.add_child(_small_label("Delay between Pi provider calls (seconds)"))
    llm_delay_spin = SpinBox.new()
    llm_delay_spin.min_value = PiAgentControllerScript.MIN_LLM_CALL_DELAY_SEC
    llm_delay_spin.max_value = PiAgentControllerScript.MAX_LLM_CALL_DELAY_SEC
    llm_delay_spin.step = 0.5
    llm_delay_spin.allow_greater = false
    llm_delay_spin.allow_lesser = false
    llm_delay_spin.tooltip_text = "Minimum wall-clock quiet time after one Pi provider response before the next provider request. First call is immediate."
    sv.add_child(llm_delay_spin)
    var delay_note = Label.new()
    delay_note.text = "Default: 6 seconds. Set 0 to disable."
    delay_note.add_theme_color_override("font_color", Color("8492ad"))
    sv.add_child(delay_note)

    sv.add_child(HSeparator.new())
    sv.add_child(_small_label("Pi session compaction"))
    var compaction_note = Label.new()
    compaction_note.text = "Pi owns agent history and native compaction. GameSmith only chooses when to trigger it and how much recent context Pi keeps verbatim."
    compaction_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    compaction_note.add_theme_color_override("font_color", Color("8492ad"))
    sv.add_child(compaction_note)
    sv.add_child(_small_label("Auto compact at estimated tokens (0 = disabled)"))
    compaction_auto_spin = SpinBox.new()
    compaction_auto_spin.min_value = 0
    compaction_auto_spin.max_value = 2000000
    compaction_auto_spin.step = 1000
    compaction_auto_spin.allow_greater = false
    compaction_auto_spin.allow_lesser = false
    sv.add_child(compaction_auto_spin)
    sv.add_child(_small_label("Keep recent tokens verbatim"))
    compaction_keep_spin = SpinBox.new()
    compaction_keep_spin.min_value = 1000
    compaction_keep_spin.max_value = 500000
    compaction_keep_spin.step = 1000
    compaction_keep_spin.allow_greater = false
    compaction_keep_spin.allow_lesser = false
    sv.add_child(compaction_keep_spin)
    compaction_status_label = Label.new()
    compaction_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    compaction_status_label.add_theme_color_override("font_color", Color("8492ad"))
    sv.add_child(compaction_status_label)

    sv.add_child(HSeparator.new())
    sv.add_child(_small_label("Global Pi provider"))
    provider_option = OptionButton.new()
    sv.add_child(provider_option)
    for id in PiProviderCatalogScript.display_names():
        provider_option.add_item(PiProviderCatalogScript.display_names()[id])
        provider_option.set_item_metadata(provider_option.item_count - 1, id)
    provider_option.item_selected.connect(_provider_changed)
    sv.add_child(_small_label("Global Pi model"))
    model_edit = LineEdit.new()
    sv.add_child(model_edit)
    sv.add_child(_small_label("Pi thinking / reasoning effort"))
    reasoning_option = OptionButton.new()
    sv.add_child(reasoning_option)
    for pair in [["Provider default (omit)", ""], ["None", "none"], ["Minimal", "minimal"], ["Low", "low"], ["Medium", "medium"], ["High", "high"], ["XHigh", "xhigh"], ["Max", "max"]]:
        reasoning_option.add_item(pair[0])
        reasoning_option.set_item_metadata(reasoning_option.item_count - 1, pair[1])
    sv.add_child(_small_label("API key passed to Pi for selected provider"))
    key_edit = LineEdit.new()
    key_edit.secret = true
    key_edit.placeholder_text = "Stored under user://host, outside game workspaces"
    sv.add_child(key_edit)
    sv.add_child(_small_label("Custom OpenAI-compatible /v1 base address"))
    custom_base_edit = LineEdit.new()
    custom_base_edit.placeholder_text = "http://127.0.0.1:1234/v1"
    sv.add_child(custom_base_edit)
    var note = Label.new()
    note.text = "GameSmith writes this provider/model config into Pi. Custom can omit an API key; OpenAI subscription delegates authentication to Pi global auth."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_color_override("font_color", Color("8492ad"))
    sv.add_child(note)

    sv.add_child(HSeparator.new())
    sv.add_child(_small_label("Current game Pi override"))
    game_override_provider = OptionButton.new()
    sv.add_child(game_override_provider)
    game_override_provider.add_item("Use global default")
    game_override_provider.set_item_metadata(0, "")
    for id in PiProviderCatalogScript.display_names():
        game_override_provider.add_item(PiProviderCatalogScript.display_names()[id])
        game_override_provider.set_item_metadata(game_override_provider.item_count - 1, id)
    sv.add_child(_small_label("Current game Pi model override"))
    game_override_model = LineEdit.new()
    game_override_model.placeholder_text = "Blank = use global model"
    sv.add_child(game_override_model)

    var actions = HBoxContainer.new()
    actions.add_theme_constant_override("separation", 8)
    root_box.add_child(actions)
    compact_now_button = Button.new()
    compact_now_button.text = "Compact now"
    compact_now_button.tooltip_text = "Summarize older context now using the current game's provider/model."
    compact_now_button.pressed.connect(_compact_now_from_settings)
    actions.add_child(compact_now_button)
    var action_spacer = Control.new()
    action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    actions.add_child(action_spacer)
    var cancel = Button.new()
    cancel.text = "Cancel"
    cancel.pressed.connect(_close_settings)
    actions.add_child(cancel)
    var save = Button.new()
    save.text = "Save"
    save.pressed.connect(_save_settings)
    actions.add_child(save)


func _small_label(text: String) -> Label:
    var l = Label.new(); l.text = text; l.add_theme_color_override("font_color", Color("aab6cf")); return l

func _refresh_library() -> void:
    var list: VBoxContainer = library_layer.find_child("GamesList", true, false)
    for child in list.get_children(): child.queue_free()
    var games = store.list_games()
    if games.is_empty():
        var empty = PanelContainer.new(); empty.custom_minimum_size.y = 160; list.add_child(empty)
        var center = CenterContainer.new(); empty.add_child(center)
        var text = Label.new(); text.text = "No games yet. Create one, then tell the agent what to build."; text.add_theme_color_override("font_color", Color("7f8eaa")); center.add_child(text)
        return
    for game in games:
        var card = PanelContainer.new(); card.custom_minimum_size.y = 60; list.add_child(card)
        var margin = MarginContainer.new(); margin.add_theme_constant_override("margin_left", 14); margin.add_theme_constant_override("margin_right", 10); margin.add_theme_constant_override("margin_top", 7); margin.add_theme_constant_override("margin_bottom", 7); card.add_child(margin)
        var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 6); margin.add_child(row)
        var label = Label.new(); label.text = game; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size", 19); row.add_child(label)
        var open = Button.new(); open.size_flags_vertical = Control.SIZE_SHRINK_CENTER; open.text = "Open"; open.pressed.connect(func(): _open_game(game)); row.add_child(open)
        var folder = Button.new(); folder.size_flags_vertical = Control.SIZE_SHRINK_CENTER; folder.text = "Folder"; folder.pressed.connect(func(): _open_game_folder_named(game)); row.add_child(folder)
        var rename = Button.new(); rename.size_flags_vertical = Control.SIZE_SHRINK_CENTER; rename.text = "Rename"; rename.pressed.connect(func(): _open_rename(game)); row.add_child(rename)
        var del = Button.new(); del.size_flags_vertical = Control.SIZE_SHRINK_CENTER; del.text = "Delete"; del.pressed.connect(func(): _ask_delete(game)); row.add_child(del)

func _show_library() -> void:
    current_game = ""
    generated_input_states.clear()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if is_instance_valid(runner): runner.queue_free()
    runner = null
    if is_instance_valid(agent): agent.queue_free()
    agent = null
    get_tree().paused = false
    background.visible = true
    library_layer.visible = true; play_hud.visible = false; chat_overlay.visible = false
    _refresh_library()

func _create_game() -> void:
    var result = store.create_game(name_edit.text)
    if result.ok:
        new_game_dialog.visible = false
        _open_game(result.name)
    else:
        _toast(str(result.error))

func _open_game(name: String) -> void:
    current_game = name
    AppLoggerScript.global_event("game.open", "name=%s" % name)
    AppLoggerScript.game_event(name, "game.open", "workspace=%s" % ProjectSettings.globalize_path(store.game_path(name)))
    background.visible = false
    library_layer.visible = false; play_hud.visible = true
    game_title_label.text = name
    var git_state = store.ensure_game_repo(name)
    if not bool(git_state.get("ok", false)):
        AppLoggerScript.game_event(name, "git.recovery_failed", "code=%s output=%s" % [str(git_state.get("code", "")), str(git_state.get("output", "")).left(1000)], "WARN")
    elif bool(git_state.get("recovered", false)):
        AppLoggerScript.game_event(name, "git.recovered", "missing Git metadata was recreated and current workspace captured as baseline", "WARN")
    runner = GameRunnerScript.new(); runner.name = "GeneratedGameRunner"; runner.process_mode = Node.PROCESS_MODE_PAUSABLE; add_child(runner); move_child(runner, 2)
    runner.load_succeeded.connect(_on_load_success)
    runner.load_failed.connect(func(msg): AppLoggerScript.game_event(name, "game.load_failed", str(msg), "ERROR"); _toast(msg))
    tools = GameToolsScript.new(store.game_path(name), runner)
    agent = PiAgentControllerScript.new(); add_child(agent); agent.configure(name, tools)
    agent.status_changed.connect(func(text): status_label.text = text)
    agent.assistant_message.connect(func(text): _append_chat("assistant", text))
    agent.llm_snippet.connect(func(kind, text): _append_chat(kind, text))
    if agent.has_signal("llm_stream_delta"):
        agent.llm_stream_delta.connect(_append_stream_delta)
    if agent.has_signal("llm_stream_end"):
        agent.llm_stream_end.connect(_end_stream_block)
    agent.finished.connect(_on_agent_finished)
    _load_transcript()
    if FileAccess.file_exists(store.game_path(name).path_join("main.gd")):
        var result: Dictionary = runner.load_game(store.game_path(name))
        if not result.ok and store.has_working_snapshot(name):
            var fallback: Dictionary = runner.load_game(metadata.snapshot_dir(name))
            if fallback.ok: _toast("Workspace candidate is broken; launched the last working snapshot.")
    else:
        _set_chat_visible(true)
        _append_chat("system", "This workspace is empty. Tell the agent what game to build.")

func _on_load_success(_version: int) -> void:
    if current_game != "":
        _reserve_host_canvas_layers()
        store.save_working_snapshot(current_game)
        if chat_overlay.visible:
            # A freshly loaded game may capture the mouse or add full-screen Controls in _ready().
            # Remember its intended gameplay mouse mode, then reassert host-chat input ownership.
            gameplay_mouse_mode = Input.mouse_mode
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            _suspend_generated_input()
        AppLoggerScript.game_event(current_game, "game.reload", "load_version=%d ok=true" % _version)
        _toast("Game reloaded successfully.")

func _reserve_host_canvas_layers() -> void:
    if not is_instance_valid(runner) or not runner.has_active_game():
        return
    _cap_generated_canvas_layers(runner.active_game)

func _cap_generated_canvas_layers(node: Node) -> void:
    if node is CanvasLayer and node.layer >= HOST_UI_CANVAS_LAYER:
        AppLoggerScript.game_event(current_game, "ui.layer_clamped", "generated CanvasLayer %s layer=%d -> %d" % [node.name, node.layer, HOST_UI_CANVAS_LAYER - 1], "WARN")
        node.layer = HOST_UI_CANVAS_LAYER - 1
    for child in node.get_children():
        _cap_generated_canvas_layers(child)

func _send_chat() -> void:
    var text = chat_input.text.strip_edges()
    if text == "" or agent == null or agent.busy: return
    chat_input.text = ""
    _set_chat_busy_controls(true)
    _append_chat("user", text)
    agent.send_player_request(text)

func _set_chat_busy_controls(is_busy: bool) -> void:
    if is_instance_valid(chat_input):
        chat_input.editable = not is_busy
    if is_instance_valid(send_button):
        send_button.disabled = is_busy
    if is_instance_valid(library_button):
        library_button.disabled = is_busy
    if not is_busy and chat_overlay.visible and not settings_dialog.visible and is_instance_valid(chat_input):
        chat_input.grab_focus()

func _append_chat(role: String, text: String) -> void:
    var label = {"user": "YOU", "assistant": "AGENT", "thinking": "THINK", "tool": "TOOL"}.get(role, "HOST")
    var color = {"user": "9bb7ff", "assistant": "c2f0cb", "thinking": "6f7ea3", "tool": "e5b978"}.get(role, "8393b2")
    transcript_view.append_text("[color=#%s][b]%s[/b][/color]\n%s\n\n" % [color, label, _escape_bbcode(text)])
    await get_tree().process_frame
    transcript_view.scroll_to_line(maxi(0, transcript_view.get_line_count() - 1))

func _append_stream_delta(kind: String, text: String) -> void:
    if text == "":
        return
    if stream_open_kind != kind:
        if stream_open_kind != "":
            transcript_view.append_text("\n\n")
        var label = {"assistant": "AGENT", "thinking": "THINK"}.get(kind, "AGENT")
        var color = {"assistant": "c2f0cb", "thinking": "6f7ea3"}.get(kind, "c2f0cb")
        transcript_view.append_text("[color=#%s][b]%s[/b][/color]\n" % [color, label])
        stream_open_kind = kind
    transcript_view.append_text(_escape_bbcode(text))
    transcript_view.scroll_to_line(maxi(0, transcript_view.get_line_count() - 1))

func _end_stream_block(kind: String) -> void:
    if stream_open_kind == kind:
        transcript_view.append_text("\n\n")
        stream_open_kind = ""

func _escape_bbcode(text: String) -> String:
    # Godot's documented RichTextLabel escaping pattern: blocking opening
    # brackets is enough to prevent user/model/tool text from becoming tags.
    return text.replace("[", "[lb]")

func _load_transcript() -> void:
    transcript_view.clear()
    stream_open_kind = ""
    for entry in transcript.read_all(current_game):
        _append_chat(str(entry.get("role", "system")), str(entry.get("content", "")))

func _set_chat_visible(visible: bool) -> void:
    if current_game == "": return
    if visible:
        if chat_overlay.visible:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            chat_input.grab_focus()
            return
        gameplay_mouse_mode = Input.mouse_mode
        chat_overlay.visible = true
        get_tree().paused = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _suspend_generated_input()
        chat_input.grab_focus()
    else:
        _restore_generated_input()
        chat_overlay.visible = false
        Input.mouse_mode = gameplay_mouse_mode
        get_tree().paused = false

func _suspend_generated_input() -> void:
    generated_input_states.clear()
    if not is_instance_valid(runner) or not runner.has_active_game():
        return
    _suspend_generated_input_node(runner.active_game)

func _suspend_generated_input_node(node: Node) -> void:
    var state = {"node": node, "process_mode": node.process_mode}
    node.process_mode = Node.PROCESS_MODE_DISABLED
    if node is Control:
        state["mouse_filter"] = node.mouse_filter
        node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    generated_input_states.append(state)
    for child in node.get_children():
        _suspend_generated_input_node(child)

func _restore_generated_input() -> void:
    # Restore parents before children so explicit child process modes remain exact.
    for entry in generated_input_states:
        var node = entry.get("node")
        if not is_instance_valid(node):
            continue
        node.process_mode = int(entry.get("process_mode", Node.PROCESS_MODE_INHERIT))
        if node is Control and entry.has("mouse_filter"):
            node.mouse_filter = int(entry.get("mouse_filter", Control.MOUSE_FILTER_STOP))
    generated_input_states.clear()

func _return_to_library() -> void:
    if is_instance_valid(agent) and agent.busy:
        AppLoggerScript.game_event(current_game, "navigation.blocked", "return_to_library while agent busy", "WARN")
        _toast("Wait for the agent to finish before returning to the library.")
        return
    if current_game != "": AppLoggerScript.game_event(current_game, "game.close", "return_to_library")
    _show_library()

func _on_agent_finished(_ok: bool) -> void:
    _set_chat_busy_controls(false)

func _open_global_logs() -> void:
    AppLoggerScript.global_event("logs.open", "global")
    OS.shell_open(ProjectSettings.globalize_path(AppLoggerScript.global_log_path().get_base_dir()))

func _open_game_logs() -> void:
    if current_game == "": return
    AppLoggerScript.game_event(current_game, "logs.open", "game")
    OS.shell_open(ProjectSettings.globalize_path(AppLoggerScript.game_log_path(current_game).get_base_dir()))

func _open_folder() -> void:
    if current_game == "": return
    _open_game_folder_named(current_game)

func _open_game_folder_named(name: String) -> void:
    if name == "": return
    OS.shell_open(ProjectSettings.globalize_path(store.game_path(name)))

func _open_rename(name: String = "") -> void:
    rename_target = name if name != "" else current_game
    if rename_target == "": return
    rename_edit.text = rename_target
    rename_dialog.popup_centered(Vector2i(430, 150))

func _rename_game() -> void:
    var old = rename_target
    if old == "": return
    var result: Dictionary = store.rename_game(old, rename_edit.text)
    if not result.get("ok", false): _toast(str(result.get("error", "Rename failed."))); return
    var new_name = str(result.get("name", old))
    if current_game == old:
        current_game = new_name
        game_title_label.text = current_game
        tools.workspace = store.game_path(current_game)
        agent.configure(current_game, tools)
    else:
        _refresh_library()
    rename_target = ""
    _toast("Renamed to %s." % new_name)

func _ask_delete(name: String) -> void:
    pending_delete = name
    delete_dialog.dialog_text = "Delete ‘%s’, its Git history, transcript, and host metadata? This cannot be undone from the UI." % name
    delete_dialog.popup_centered(Vector2i(500, 160))

func _delete_game_confirmed() -> void:
    if pending_delete == "": return
    var target = pending_delete
    pending_delete = ""
    if current_game == target:
        current_game = ""
    store.delete_game(target)
    _show_library()

func _open_settings() -> void:
    var settings = metadata.global_settings()
    var creds = metadata.credentials()
    var id = str(settings.get("provider", "openrouter"))
    _select_provider_id(id)
    model_edit.text = str(settings.get("model", PiProviderCatalogScript.defaults().get(id, "")))
    key_edit.text = str(creds.get(id, ""))
    custom_base_edit.text = str(settings.get("custom_base_url", ""))
    _select_reasoning_effort(str(settings.get("reasoning_effort", "")))
    agent_steps_spin.value = clampi(int(settings.get("max_agent_steps", PiAgentControllerScript.DEFAULT_MAX_STEPS)), PiAgentControllerScript.MIN_AGENT_STEPS, PiAgentControllerScript.MAX_AGENT_STEPS)
    llm_delay_spin.value = clampf(float(settings.get("llm_call_delay_sec", PiAgentControllerScript.DEFAULT_LLM_CALL_DELAY_SEC)), PiAgentControllerScript.MIN_LLM_CALL_DELAY_SEC, PiAgentControllerScript.MAX_LLM_CALL_DELAY_SEC)
    compaction_auto_spin.value = clampi(int(settings.get("compaction_auto_tokens", 100000)), 0, 2000000)
    compaction_keep_spin.value = clampi(int(settings.get("compaction_keep_recent_tokens", 20000)), 1000, 500000)
    if current_game != "":
        var game_meta = metadata.read_game(current_game)
        _select_game_provider_id(str(game_meta.get("provider_override", "")))
        game_override_model.text = str(game_meta.get("model_override", ""))
        game_override_provider.disabled = false
        game_override_model.editable = true
        var estimated = agent.context_tokens() if is_instance_valid(agent) and agent.has_method("context_tokens") else 0
        compaction_status_label.text = "Current Pi context: ~%d tokens." % estimated if estimated > 0 else "Pi context size is available after the first provider response."
        compact_now_button.disabled = not is_instance_valid(agent) or agent.busy
    else:
        game_override_provider.select(0)
        game_override_model.text = ""
        game_override_provider.disabled = true
        game_override_model.editable = false
        compaction_status_label.text = "Open a game to compact its conversation manually."
        compact_now_button.disabled = true
    settings_dialog.visible = true

func _close_settings() -> void:
    settings_dialog.visible = false

func _compact_now_from_settings() -> void:
    if current_game == "" or not is_instance_valid(agent):
        compaction_status_label.text = "Open a game first."
        return
    if agent.busy:
        compaction_status_label.text = "Wait for the current agent request to finish."
        return

    compact_now_button.disabled = true
    compaction_status_label.text = "Compacting…"
    _set_chat_busy_controls(true)
    settings_dialog.visible = false
    _append_chat("system", "Compacting conversation…")

    var result: Dictionary = await agent.compact_now()
    var chat_result = ""
    if bool(result.get("ok", false)):
        chat_result = "Compaction finished: ~%d → ~%d estimated tokens." % [int(result.get("tokens_before", 0)), int(result.get("tokens_after", 0))]
        compaction_status_label.text = chat_result
    elif bool(result.get("no_op", false)):
        chat_result = "Compaction skipped: " + str(result.get("error", "Nothing to compact."))
        compaction_status_label.text = chat_result
    else:
        chat_result = "Compaction failed: " + str(result.get("error", "Unknown error."))
        compaction_status_label.text = chat_result

    _append_chat("system", chat_result)
    compact_now_button.disabled = false
    _set_chat_busy_controls(false)


func _provider_changed(index: int) -> void:
    var id = str(provider_option.get_item_metadata(index)); var settings = metadata.global_settings(); var creds = metadata.credentials()
    model_edit.text = str(PiProviderCatalogScript.defaults().get(id, settings.get("model", "")))
    key_edit.text = str(creds.get(id, ""))

func _save_settings() -> void:
    var id = str(provider_option.get_item_metadata(provider_option.selected))
    var settings = metadata.global_settings()
    settings.provider = id
    settings.model = model_edit.text.strip_edges()
    settings.custom_base_url = custom_base_edit.text.strip_edges()
    settings.reasoning_effort = str(reasoning_option.get_item_metadata(reasoning_option.selected))
    settings.max_agent_steps = int(agent_steps_spin.value)
    settings.llm_call_delay_sec = float(llm_delay_spin.value)
    settings.compaction_auto_tokens = int(compaction_auto_spin.value)
    settings.compaction_keep_recent_tokens = int(compaction_keep_spin.value)
    metadata.save_global_settings(settings)
    AppLoggerScript.global_event("settings.save", "provider=%s model=%s reasoning_effort=%s max_agent_steps=%d llm_call_delay_sec=%.1f compaction_auto_tokens=%d compaction_keep_recent_tokens=%d" % [id, settings.model, settings.reasoning_effort, int(settings.max_agent_steps), float(settings.llm_call_delay_sec), int(settings.compaction_auto_tokens), int(settings.compaction_keep_recent_tokens)])
    var creds = metadata.credentials(); creds[id] = key_edit.text.strip_edges(); metadata.save_credentials(creds)
    if current_game != "":
        var game_meta = metadata.read_game(current_game)
        game_meta.provider_override = str(game_override_provider.get_item_metadata(game_override_provider.selected))
        game_meta.model_override = game_override_model.text.strip_edges()
        metadata.write_game(current_game, game_meta)
        if is_instance_valid(agent) and agent.has_method("settings_changed"):
            agent.settings_changed()
    settings_dialog.visible = false
    _toast("Settings saved.")

func _select_provider_id(id: String) -> void:
    for i in provider_option.item_count:
        if str(provider_option.get_item_metadata(i)) == id:
            provider_option.select(i); return
    provider_option.select(0)

func _select_game_provider_id(id: String) -> void:
    for i in game_override_provider.item_count:
        if str(game_override_provider.get_item_metadata(i)) == id:
            game_override_provider.select(i); return
    game_override_provider.select(0)

func _select_reasoning_effort(value: String) -> void:
    for i in reasoning_option.item_count:
        if str(reasoning_option.get_item_metadata(i)) == value:
            reasoning_option.select(i); return
    reasoning_option.select(0)

func _toast(text: String) -> void:
    toast_label.text = text
    var token = Time.get_ticks_msec(); toast_label.set_meta("toast_token", token)
    await get_tree().create_timer(4.0, true).timeout
    if toast_label.get_meta("toast_token", -1) == token: toast_label.text = ""

func _maybe_capture() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture="):
            var path = arg.trim_prefix("--capture=")
            await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
            get_viewport().get_texture().get_image().save_png(path)
            get_tree().quit()
