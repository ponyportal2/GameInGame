extends RefCounted

const U = preload("res://src/ui/workspace_ui.gd")
const T = preload("res://src/ui/theme_factory.gd")
const Providers = preload("res://src/pi/pi_provider_catalog.gd")
const Agent = preload("res://src/agent/pi_agent_controller.gd")

static func overlay(app, name: String) -> Control:
    var node = Control.new()
    node.name = name
    node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    node.process_mode = Node.PROCESS_MODE_ALWAYS
    node.mouse_filter = Control.MOUSE_FILTER_STOP
    node.visible = false
    app.host_ui_root.add_child(node)
    var shade = ColorRect.new()
    shade.color = Color("080d10d9")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    node.add_child(shade)
    return node

static func panel(parent: Node, width: int, height: int) -> PanelContainer:
    var node = PanelContainer.new()
    parent.add_child(node)
    node.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    node.offset_left = -width / 2.0
    node.offset_right = width / 2.0
    node.offset_top = -height / 2.0
    node.offset_bottom = height / 2.0
    return node

static func page(tabs: TabContainer, title: String) -> VBoxContainer:
    var scroll = ScrollContainer.new()
    scroll.name = title
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    tabs.add_child(scroll)
    var inset = U.margin(scroll, 4, 10)
    inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return U.column(inset, 12)

static func field(parent: Node, title: String, control: Control, description: String = "") -> void:
    var group = U.column(parent, 6)
    U.label(group, title, 13)
    group.add_child(control)
    if description != "":
        U.paragraph(group, description)

static func spin(minimum: float, maximum: float, step: float) -> SpinBox:
    var node = SpinBox.new()
    node.min_value = minimum
    node.max_value = maximum
    node.step = step
    return node

static func provider(include_default: bool = false) -> OptionButton:
    var node = OptionButton.new()
    if include_default:
        node.add_item("Use global default")
        node.set_item_metadata(0, "")
    for id in Providers.display_names():
        node.add_item(Providers.display_names()[id])
        node.set_item_metadata(node.item_count - 1, id)
    return node

static func build(app) -> void:
    app.settings_dialog = overlay(app, "SettingsOverlay")
    var root = U.column(U.margin(panel(app.settings_dialog, 760, 620), 18, 14), 16)
    var head = U.row(root)
    var title = U.column(head, 2)
    U.label(title, "Settings", 25)
    U.label(title, "A workspace that works your way.", 13, T.MUTED)
    U.space(head)
    U.button(head, "Close", app._close_settings, "QuietButton")
    var tabs = TabContainer.new()
    tabs.name = "SettingsTabs"
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(tabs)
    var model = page(tabs, "Model")
    app.provider_option = provider()
    app.provider_option.item_selected.connect(app._provider_changed)
    field(model, "Provider", app.provider_option)
    app.model_edit = LineEdit.new()
    app.model_edit.placeholder_text = "Provider model ID"
    field(model, "Model", app.model_edit)
    app.key_edit = LineEdit.new()
    app.key_edit.secret = true
    app.key_edit.placeholder_text = "Enter your API key"
    field(model, "API key", app.key_edit, "Stored locally, outside your games. Subscription providers use your Pi sign-in.")
    app.reasoning_option = OptionButton.new()
    for pair in [["Provider default", ""], ["None", "none"], ["Minimal", "minimal"], ["Low", "low"], ["Medium", "medium"], ["High", "high"], ["Extra high", "xhigh"], ["Max", "max"]]:
        app.reasoning_option.add_item(pair[0])
        app.reasoning_option.set_item_metadata(app.reasoning_option.item_count - 1, pair[1])
    field(model, "Reasoning effort", app.reasoning_option)
    app.custom_base_edit = LineEdit.new()
    app.custom_base_edit.placeholder_text = "http://127.0.0.1:1234/v1"
    field(model, "Custom API address", app.custom_base_edit, "For a custom OpenAI-compatible provider. Other providers ignore this address.")
    var agent_page = page(tabs, "Agent & testing")
    app.agent_steps_spin = spin(Agent.MIN_AGENT_STEPS, Agent.MAX_AGENT_STEPS, 1)
    field(agent_page, "Maximum turns per request", app.agent_steps_spin, "Default: 150. Limit how long the agent can work on one request.")
    app.llm_delay_spin = spin(Agent.MIN_LLM_CALL_DELAY_SEC, Agent.MAX_LLM_CALL_DELAY_SEC, 0.5)
    field(agent_page, "Delay between model calls · seconds", app.llm_delay_spin, "Default: 6. Set to 0 for immediate calls.")
    agent_page.add_child(HSeparator.new())
    app.auto_reload_check = CheckBox.new()
    app.auto_reload_check.text = "Automatically approve agent reload requests"
    agent_page.add_child(app.auto_reload_check)
    U.paragraph(agent_page, "Start or reload the live game without waiting for Shift+F5 or Allow Reload. Applies to all harnesses. Off by default.")
    U.label(agent_page, "Separate game tests", 18)
    app.rendered_tests_check = CheckBox.new()
    app.rendered_tests_check.text = "Allow rendered agent tests (minimized window)"
    agent_page.add_child(app.rendered_tests_check)
    U.paragraph(agent_page, "Headless tests are always available. Rendered tests open minimized, without taking focus. Neither interrupts your live game.")
    var conversation = page(tabs, "Conversation")
    U.paragraph(conversation, "Summarize older conversation to make room for new work. Recent messages stay intact.")
    app.compaction_auto_spin = spin(0, 2000000, 1000)
    field(conversation, "Automatically compact at · estimated tokens", app.compaction_auto_spin, "Pi and Command-code: checked between requests. OpenCode, Codex, Cline, Cursor, Grok Build, AGY, Kimi Code, Kiro CLI and Kilo CLI handle their own compaction. Set to 0 to disable GameSmith’s trigger; the harness can still compact automatically.")
    app.compaction_keep_spin = spin(1000, 500000, 1000)
    field(conversation, "Recent tokens to keep", app.compaction_keep_spin)
    conversation.add_child(HSeparator.new())
    app.compaction_status_label = U.paragraph(conversation, "Open a game to see its context usage.")
    app.compact_now_button = U.button(conversation, "Compact now", app._compact_now_from_settings)
    app.compact_now_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    var game = page(tabs, "This game")
    app.game_harness_option = OptionButton.new()
    for pair in [["Pi", "pi"], ["Command-code", "command-code"], ["OpenCode", "opencode"], ["Codex", "codex"], ["Cline", "cline"], ["Cursor", "cursor"], ["Grok Build", "grok-build"], ["AGY (experimental)", "agy"], ["Kimi Code", "kimi"], ["Kiro CLI", "kiro"], ["Kilo CLI", "kilo"]]:
        app.game_harness_option.add_item(pair[0])
        app.game_harness_option.set_item_metadata(app.game_harness_option.item_count - 1, pair[1])
    field(game, "Coding harness", app.game_harness_option, "Switch after the agent finishes or is stopped. Files and chat stay with the game. Each harness keeps its own session; switching back resumes it. Save, then reopen settings to configure the selected harness.")
    app.codex_new_session_button = U.button(game, "Start new Codex session", app._request_new_codex_session, "QuietButton")
    app.codex_new_session_button.visible = false
    U.paragraph(game, "Override the global model for the open game. Other games keep their own settings.")
    app.game_override_provider = provider(true)
    field(game, "Provider override", app.game_override_provider)
    app.game_override_model = LineEdit.new()
    app.game_override_model.placeholder_text = "Use global model"
    field(game, "Model override", app.game_override_model, "Leave blank to use the global model. Open a game to change these settings.")
    var footer = U.row(root)
    U.label(footer, "Changes apply after you save.", 12, T.MUTED)
    U.space(footer)
    U.button(footer, "Cancel", app._close_settings, "QuietButton")
    U.button(footer, "Save", app._save_settings, "PrimaryButton")
    app.codex_session_dialog = overlay(app, "CodexSessionOverlay")
    var confirmation = U.column(U.margin(panel(app.codex_session_dialog, 540, 290), 22, 20), 16)
    app.native_session_title = U.label(confirmation, "Start a new Codex session?", 24)
    app.native_session_description = U.paragraph(confirmation, "The next message starts a fresh Codex conversation. The previous session reference is archived, and your chat and game files are kept. The old conversation will not be included in the new agent context.")
    U.space(confirmation, true)
    var actions = U.row(confirmation)
    U.space(actions)
    U.button(actions, "Cancel", app._cancel_new_codex_session, "QuietButton")
    U.button(actions, "Start new session", app._confirm_new_codex_session, "PrimaryButton")

static func build_new_game(app) -> void:
    app.new_game_dialog = overlay(app, "NewGameOverlay")
    var root = U.column(U.margin(panel(app.new_game_dialog, 500, 410), 22, 20), 16)
    U.label(root, "A NEW BEGINNING", 11, T.ACCENT)
    U.label(root, "What will you make?", 28)
    U.paragraph(root, "Give your game a name. You can shape the idea with the agent in chat and rename it anytime.")
    app.name_edit = LineEdit.new()
    app.name_edit.placeholder_text = "Neon Asteroids"
    field(root, "Game name", app.name_edit)
    app.harness_option = OptionButton.new()
    app.harness_option.add_item("Pi")
    app.harness_option.set_item_metadata(0, "pi")
    app.harness_option.add_item("Command-code")
    app.harness_option.set_item_metadata(1, "command-code")
    app.harness_option.add_item("OpenCode")
    app.harness_option.set_item_metadata(2, "opencode")
    app.harness_option.add_item("Codex")
    app.harness_option.set_item_metadata(3, "codex")
    app.harness_option.add_item("Cline")
    app.harness_option.set_item_metadata(4, "cline")
    app.harness_option.add_item("Cursor")
    app.harness_option.set_item_metadata(5, "cursor")
    app.harness_option.add_item("Grok Build")
    app.harness_option.set_item_metadata(6, "grok-build")
    app.harness_option.add_item("AGY (experimental)")
    app.harness_option.set_item_metadata(7, "agy")
    app.harness_option.add_item("Kimi Code")
    app.harness_option.set_item_metadata(8, "kimi")
    app.harness_option.add_item("Kiro CLI")
    app.harness_option.set_item_metadata(9, "kiro")
    app.harness_option.add_item("Kilo CLI")
    app.harness_option.set_item_metadata(10, "kilo")
    field(root, "Coding harness", app.harness_option, "Command-code, OpenCode, Codex, Cline, Grok Build, AGY, Kimi Code, Kiro CLI and Kilo CLI use their own model and provider settings. Cursor uses Auto; the model selected in its editor or interactive CLI is not inherited. OpenCode, Codex, Cline, Cursor, Grok Build, AGY, Kimi Code, Kiro CLI and Kilo CLI handle their own compaction. AGY support is experimental; live model execution has not been verified.")
    app.name_edit.text_submitted.connect(func(_text): app._create_game())
    U.space(root, true)
    var actions = U.row(root)
    U.space(actions)
    U.button(actions, "Cancel", func(): app.new_game_dialog.visible = false, "QuietButton")
    U.button(actions, "Create", app._create_game, "PrimaryButton")

static func build_management(app) -> void:
    app.rename_dialog = overlay(app, "RenameGameOverlay")
    var rename = U.column(U.margin(panel(app.rename_dialog, 500, 280), 22, 20), 16)
    U.label(rename, "Rename game", 25)
    U.paragraph(rename, "Your conversation, files, and working snapshot move with your game.")
    app.rename_edit = LineEdit.new()
    field(rename, "Game name", app.rename_edit)
    app.rename_edit.text_submitted.connect(func(_text): app._rename_game())
    U.space(rename, true)
    var rename_actions = U.row(rename)
    U.space(rename_actions)
    U.button(rename_actions, "Cancel", func(): app.rename_dialog.visible = false, "QuietButton")
    U.button(rename_actions, "Rename", app._rename_game, "PrimaryButton")
    app.delete_dialog = overlay(app, "DeleteGameOverlay")
    var deletion = U.column(U.margin(panel(app.delete_dialog, 500, 290), 22, 20), 16)
    U.label(deletion, "Delete this game?", 25)
    app.delete_game_label = U.label(deletion, "", 19, Color("f0a69a"))
    app.delete_game_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    U.paragraph(deletion, "This permanently removes the game, its conversation, history, and working snapshot. This cannot be undone.")
    U.space(deletion, true)
    var delete_actions = U.row(deletion)
    U.space(delete_actions)
    U.button(delete_actions, "Cancel", func(): app.delete_dialog.visible = false, "QuietButton")
    U.button(delete_actions, "Delete game", app._delete_game_confirmed, "DangerButton")
