extends RefCounted

# Presentation only. App owns navigation, input ownership, and runtime lifecycle.
const T = preload("res://src/ui/theme_factory.gd")

static func label(parent: Node, text: String, size: int = 15, color: Color = T.TEXT) -> Label:
    var node = Label.new()
    node.text = text
    node.add_theme_font_size_override("font_size", size)
    node.add_theme_color_override("font_color", color)
    parent.add_child(node)
    return node

static func button(parent: Node, text: String, action: Callable, variant: String = "") -> Button:
    var node = Button.new()
    node.text = text
    node.theme_type_variation = variant
    node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    node.pressed.connect(action)
    parent.add_child(node)
    return node

static func margin(parent: Node, horizontal: int = 24, vertical: int = 24) -> MarginContainer:
    var node = MarginContainer.new()
    for side in ["left", "right"]:
        node.add_theme_constant_override("margin_" + side, horizontal)
    for side in ["top", "bottom"]:
        node.add_theme_constant_override("margin_" + side, vertical)
    parent.add_child(node)
    return node

static func column(parent: Node, gap: int = 12) -> VBoxContainer:
    var node = VBoxContainer.new()
    node.add_theme_constant_override("separation", gap)
    parent.add_child(node)
    return node

static func row(parent: Node, gap: int = 10) -> HBoxContainer:
    var node = HBoxContainer.new()
    node.add_theme_constant_override("separation", gap)
    parent.add_child(node)
    return node

static func space(parent: Node, vertical: bool = false) -> Control:
    var node = Control.new()
    if vertical:
        node.size_flags_vertical = Control.SIZE_EXPAND_FILL
    else:
        node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(node)
    return node

static func paragraph(parent: Node, text: String) -> Label:
    var node = label(parent, text, 14, T.MUTED)
    node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return node

static func clear_search(app) -> void:
    app.library_search.text = ""
    refresh_library(app)

static func build_library(app) -> void:
    var shell = row(app.library_layer, 0)
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var sidebar = PanelContainer.new()
    sidebar.custom_minimum_size.x = 212
    sidebar.add_theme_stylebox_override("panel", T.box(Color("151a1d"), 0, T.BORDER, 0))
    shell.add_child(sidebar)
    var nav = column(margin(sidebar, 22, 28), 20)
    var brand = row(nav, 10)
    label(brand, "◈", 29, T.ACCENT)
    label(brand, "GameSmith", 21)
    label(nav, "YOUR CREATIVE SPACE", 10, T.MUTED)
    var games_button = button(nav, "  Games", func(): clear_search(app), "QuietButton")
    games_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    games_button.add_theme_stylebox_override("normal", T.box(Color("2a382c"), 8))
    games_button.add_theme_color_override("font_color", T.ACCENT)
    space(nav, true)
    var settings = button(nav, "Settings", app._open_settings, "QuietButton")
    settings.alignment = HORIZONTAL_ALIGNMENT_LEFT
    var logs = button(nav, "Logs", app._open_global_logs, "QuietButton")
    logs.alignment = HORIZONTAL_ALIGNMENT_LEFT
    nav.add_child(HSeparator.new())
    label(nav, "Made here. Stored here.", 12, T.MUTED)
    label(nav, "Local game workspaces", 11, Color("65767d"))
    var content = margin(shell, 40, 32)
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var main = column(content, 22)
    var header = row(main)
    label(header, "LIBRARY", 11, T.ACCENT)
    space(header)
    button(header, "+ New Game", app._open_new_game, "PrimaryButton")
    var hero = column(main, 4)
    label(hero, "Your ideas, made playable.", 32)
    label(hero, "Build a game through conversation. Play, refine, repeat.", 15, T.MUTED)
    main.add_child(HSeparator.new())
    var tools = row(main)
    app.library_count = label(tools, "Your games", 18)
    space(tools)
    app.library_search = LineEdit.new()
    app.library_search.custom_minimum_size.x = 246
    app.library_search.placeholder_text = "Find a game…"
    app.library_search.clear_button_enabled = true
    app.library_search.text_changed.connect(func(_text): refresh_library(app))
    tools.add_child(app.library_search)
    var scroll = ScrollContainer.new()
    scroll.name = "GameScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    main.add_child(scroll)
    var grid = GridContainer.new()
    grid.name = "GamesList"
    grid.columns = 2
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 16)
    grid.add_theme_constant_override("v_separation", 16)
    scroll.add_child(grid)
    scroll.resized.connect(func(): grid.columns = 2 if scroll.size.x >= 800 else 1)
    label(main, "Games open in chat. You choose when to run them.", 12, T.MUTED)

static func refresh_library(app) -> void:
    var grid = app.library_layer.find_child("GamesList", true, false)
    for child in grid.get_children():
        grid.remove_child(child)
        child.queue_free()
    var games = app.store.list_games()
    grid.columns = 2 if grid.get_parent().size.x >= 800 else 1
    var query = app.library_search.text.strip_edges().to_lower()
    app.library_count.text = "Your games  ·  %d" % games.size()
    var shown = 0
    for game in games:
        if query != "" and not game.to_lower().contains(query):
            continue
        shown += 1
        var card = PanelContainer.new()
        card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        card.custom_minimum_size.y = 168
        grid.add_child(card)
        var body = column(margin(card, 8, 6), 10)
        var top = row(body)
        var tile = PanelContainer.new()
        var colors = [Color("b8e986"), Color("8bc7dd"), Color("d8b6eb"), Color("ecc592")]
        var accent: Color = colors[posmod(game.hash(), colors.size())]
        tile.add_theme_stylebox_override("panel", T.box(Color(accent, 0.1), 10, Color(accent, 0.22)))
        tile.custom_minimum_size = Vector2(44, 44)
        top.add_child(tile)
        var monogram = label(tile, game.left(2).to_upper(), 21, accent)
        monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        space(top)
        var menu = MenuButton.new()
        menu.text = "•••"
        menu.theme_type_variation = "QuietButton"
        menu.tooltip_text = "Game actions"
        menu.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
        top.add_child(menu)
        var popup = menu.get_popup()
        for action in ["Open folder", "Rename", "Delete game…"]:
            popup.add_item(action)
        popup.id_pressed.connect(func(id):
            match id:
                0: app._open_game_folder_named(game)
                1: app._open_rename(game)
                2: app._ask_delete(game)
        )
        var title = label(body, game, 21)
        title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var bottom = row(body)
        var runnable = FileAccess.file_exists(app.store.game_path(game).path_join("main.gd")) or app.store.has_working_snapshot(game)
        label(bottom, "Ready to explore" if runnable else "A fresh canvas", 13, T.MUTED)
        space(bottom)
        button(bottom, "Open  →", func(): app._open_game(game), "QuietButton")
    if shown == 0:
        grid.columns = 1
        var empty = PanelContainer.new()
        empty.custom_minimum_size.y = 265
        empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(empty)
        var center = CenterContainer.new()
        empty.add_child(center)
        var body = column(center, 14)
        for node in [label(body, "◇", 44, T.ACCENT), label(body, "Your first game starts with an idea." if query == "" else "No games found", 23), label(body, "Create a workspace, then tell the agent what you imagine." if query == "" else "Try another name or clear your search.", 14, T.MUTED)]:
            node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var action = button(body, "+ New Game" if query == "" else "Clear search", app._open_new_game if query == "" else func(): clear_search(app), "PrimaryButton")
        action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

static func build_play_hud(app) -> void:
    var panel = PanelContainer.new()
    panel.position = Vector2(20, 18)
    panel.add_theme_stylebox_override("panel", T.box(Color("191e21e8"), 10, T.BORDER))
    app.play_hud.add_child(panel)
    var top = row(panel)
    app.game_title_label = label(top, "", 16)
    app.game_title_label.custom_minimum_size.x = 140
    app.game_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    app._add_execution_status(top)
    button(top, "Chat  F1", func(): app._set_chat_visible(true))
    app._add_reload_button(top)
    app.reload_notice = label(app.play_hud, "Reload requested  ·  Shift+F5 to allow  ·  F1 to view chat", 15, T.ACCENT)
    app.reload_notice.position = Vector2(24, 86)
    app.reload_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
    app.reload_notice.add_theme_stylebox_override("normal", T.box(Color("191e21ee"), 8, Color("65844d")))
    app.reload_notice.visible = false
    app.toast_label = Label.new()
    app.toast_label.add_theme_color_override("font_color", T.TEXT)
    app.toast_label.add_theme_stylebox_override("normal", T.box(Color("202a25"), 8, Color("53694b")))
    app.toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    app.host_ui_root.add_child(app.toast_label)
    app.toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    app.toast_label.offset_left = 24
    app.toast_label.offset_bottom = -22
    app.toast_label.offset_top = -64
    app.toast_label.visible = false

static func build_chat(app) -> void:
    var shade = ColorRect.new()
    shade.color = Color("101416b8")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    app.chat_overlay.add_child(shade)
    var left = MarginContainer.new()
    left.anchor_right = 0.4
    left.anchor_bottom = 1
    for side in ["left", "right", "top", "bottom"]:
        left.add_theme_constant_override("margin_" + side, 28)
    app.chat_overlay.add_child(left)
    var project = column(left, 20)
    app.library_button = button(project, "← Library", app._return_to_library, "QuietButton")
    app.library_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    label(project, "WORKSPACE", 11, T.ACCENT)
    app.workspace_title_label = label(project, "", 30)
    app.workspace_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    app.workspace_title_label.max_lines_visible = 2
    app.workspace_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    app._add_execution_status(project)
    var controls = row(project)
    app.run_game_button = button(controls, "Run Game", app._run_game, "PrimaryButton")
    app._add_reload_button(controls)
    space(project, true)
    app.workspace_welcome = column(project, 12)
    label(app.workspace_welcome, "◇", 56, T.ACCENT)
    label(app.workspace_welcome, "Imagine it.\nMake it playable.", 29)
    paragraph(app.workspace_welcome, "Describe your idea in chat. Refine it with the agent, then run your game when you’re ready.")
    space(project, true)
    app.resume_game_button = button(project, "Resume Game  Esc", func(): app._set_chat_visible(false), "PrimaryButton")
    app.resume_game_button.tooltip_text = "Return to the running game. Run Game first if nothing is running."
    label(project, "F1  Chat / play    ·    Shift+F5  Allow reload", 11, T.MUTED)
    var panel = PanelContainer.new()
    panel.anchor_left = 0.4
    panel.anchor_right = 1
    panel.anchor_bottom = 1
    panel.add_theme_stylebox_override("panel", T.box(T.SURFACE, 0, T.BORDER, 0))
    app.chat_overlay.add_child(panel)
    var box = column(margin(panel, 26, 22), 16)
    var header = row(box)
    label(header, "Conversation", 22)
    space(header)
    app.status_label = label(header, "Ready", 13, T.ACCENT)
    app.status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    app.status_label.custom_minimum_size.x = 100
    app.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    app.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    var utility = row(box, 4)
    button(utility, "Folder", app._open_folder, "QuietButton")
    button(utility, "Logs", app._open_game_logs, "QuietButton")
    app.rename_button = button(utility, "Rename", app._open_rename, "QuietButton")
    space(utility)
    button(utility, "Settings", app._open_settings, "QuietButton")
    box.add_child(HSeparator.new())
    app.approve_reload_button = button(box, "Allow Reload  Shift+F5", app._approve_agent_reload, "PrimaryButton")
    app.approve_reload_button.tooltip_text = "Allow a reload of the current workspace, including changes made while waiting."
    app.approve_reload_button.visible = false
    app.transcript_view = RichTextLabel.new()
    app.transcript_view.bbcode_enabled = true
    app.transcript_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    app.transcript_view.scroll_active = true
    box.add_child(app.transcript_view)
    var composer_panel = PanelContainer.new()
    composer_panel.add_theme_stylebox_override("panel", T.box(Color("111719"), 12, T.BORDER, 12))
    box.add_child(composer_panel)
    var composer = column(composer_panel, 8)
    app.chat_input = TextEdit.new()
    app.chat_input.placeholder_text = "What would you like to create or change?"
    app.chat_input.custom_minimum_size.y = 78
    app.chat_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    app.chat_input.add_theme_stylebox_override("normal", T.box(Color.TRANSPARENT, 6, Color.TRANSPARENT, 4))
    composer.add_child(app.chat_input)
    var actions = row(composer)
    label(actions, "Enter to send  ·  Shift+Enter for a new line", 11, T.MUTED)
    space(actions)
    app.stop_button = button(actions, "Stop", app._stop_agent, "DangerButton")
    app.stop_button.tooltip_text = "Cancel this request. Your conversation and existing edits are kept."
    app.stop_button.disabled = true
    app.send_button = button(actions, "Send", app._send_chat, "PrimaryButton")
