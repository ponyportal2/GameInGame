extends Control

const WorkspaceStoreScript = preload("res://src/core/workspace_store.gd")
const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const GameRunnerScript = preload("res://src/core/game_runner.gd")
const GameToolsScript = preload("res://src/core/game_tools.gd")
const PiAgentControllerScript = preload("res://src/agent/pi_agent_controller.gd")
const OpenCodeAgentControllerScript = preload("res://src/agent/opencode_agent_controller.gd")
const KimiAgentControllerScript = preload("res://src/agent/kimi_agent_controller.gd")
const AgyAgentControllerScript = preload("res://src/agent/agy_agent_controller.gd")
const GrokBuildAgentControllerScript = preload("res://src/agent/grok_build_agent_controller.gd")
const CursorAgentControllerScript = preload("res://src/agent/cursor_agent_controller.gd")
const ClineAgentControllerScript = preload("res://src/agent/cline_agent_controller.gd")
const CodexAgentControllerScript = preload("res://src/agent/codex_agent_controller.gd")
const CommandCodeAgentControllerScript = preload("res://src/agent/command_code_agent_controller.gd")
const TranscriptStoreScript = preload("res://src/core/transcript_store.gd")
const PiProviderCatalogScript = preload("res://src/pi/pi_provider_catalog.gd")
const ThemeFactoryScript = preload("res://src/ui/theme_factory.gd")
const AppLoggerScript = preload("res://src/core/app_logger.gd")
const LegacyDataMigratorScript = preload("res://src/core/legacy_data_migrator.gd")

const WorkspaceUIScript = preload("res://src/ui/workspace_ui.gd")
const SettingsUIScript = preload("res://src/ui/settings_ui.gd")

# Embedded PopupMenu windows render at 1024. Keep host controls below them,
# while clamping generated game layers below the host.
const HOST_UI_CANVAS_LAYER = 1023

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
var rename_dialog: Control
var delete_dialog: Control
var delete_game_label: Label
var settings_dialog: Control
var name_edit: LineEdit
var harness_option: OptionButton
var game_edit_guard
var game_harness_option: OptionButton
var codex_new_session_button: Button
var codex_session_dialog: Control
var codex_session_game := ""
var native_session_title: Label
var native_session_description: Label
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
var rendered_tests_check: CheckBox
var auto_reload_check: CheckBox
var compact_now_button: Button
var compaction_status_label: Label
var library_button: Button
var send_button: Button
var stop_button: Button
var rename_button: Button
var run_game_button: Button
var resume_game_button: Button
var reload_game_buttons: Array[Button] = []
var execution_status_labels: Array[Label] = []
var running_source_status := "Running workspace"
var reload_notice: Label
var approve_reload_button: Button
var game_override_provider: OptionButton
var game_override_model: LineEdit
var gameplay_mouse_mode := Input.MOUSE_MODE_VISIBLE
var generated_input_states: Array = []
var stream_open_kind := ""
var library_search: LineEdit
var library_count: Label
var workspace_title_label: Label
var workspace_welcome: Control

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    theme = ThemeFactoryScript.build()
    var migration = LegacyDataMigratorScript.migrate_user_data()
    store.ensure()
    preload("res://src/core/test_evidence.gd").recover_all()
    AppLoggerScript.global_event("app.startup", "user_data=%s legacy_source=%s migrated=%d skipped=%d" % [ProjectSettings.globalize_path("user://"), str(migration.get("source_found", false)), int(migration.get("copied", 0)), int(migration.get("skipped", 0))])
    _build_ui()
    if not InputMap.has_action("approve_game_reload"):
        InputMap.add_action("approve_game_reload")
        var shortcut = InputEventKey.new()
        shortcut.physical_keycode = KEY_F5
        shortcut.shift_pressed = true
        InputMap.action_add_event("approve_game_reload", shortcut)
    _show_library()
    _maybe_capture()

func _process(_delta: float) -> void:
    # Poll global action state because generated games may consume _input() before the host.
    if current_game != "" and not _host_modal_open() and Input.is_action_just_pressed("toggle_chat"):
        _set_chat_visible(not chat_overlay.visible)
    if current_game != "" and Input.is_action_just_pressed("approve_game_reload"):
        _approve_agent_reload()

func _input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    if event.keycode == KEY_ESCAPE and codex_session_dialog.visible:
        _cancel_new_codex_session()
        get_viewport().set_input_as_handled()
        return
    if event.keycode == KEY_ESCAPE and (rename_dialog.visible or delete_dialog.visible):
        get_viewport().set_input_as_handled()
        rename_dialog.visible = false
        delete_dialog.visible = false
        return
    if event.keycode == KEY_ESCAPE and settings_dialog.visible:
        get_viewport().set_input_as_handled()
        _close_settings()
        return
    if event.keycode == KEY_ESCAPE and new_game_dialog.visible:
        get_viewport().set_input_as_handled()
        new_game_dialog.visible = false
        return
    if event.keycode == KEY_ESCAPE and chat_overlay.visible:
        get_viewport().set_input_as_handled()
        _set_chat_visible(false)
        return
    if chat_overlay.visible and not _host_modal_open() and chat_input.has_focus() and not event.shift_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
        # Handle this before TextEdit sees it, otherwise Enter inserts a newline.
        get_viewport().set_input_as_handled()
        _send_chat()

func _host_modal_open() -> bool:
    return settings_dialog.visible or codex_session_dialog.visible or new_game_dialog.visible or rename_dialog.visible or delete_dialog.visible

func _build_ui() -> void:
    host_ui_canvas = CanvasLayer.new(); host_ui_canvas.layer = HOST_UI_CANVAS_LAYER; add_child(host_ui_canvas)
    host_ui_root = Control.new(); host_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.theme = theme; host_ui_canvas.add_child(host_ui_root)
    host_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    background = ColorRect.new(); background.color = ThemeFactoryScript.BACKGROUND; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(background)
    game_layer = Control.new(); game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(game_layer)
    game_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    library_layer = Control.new(); library_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); host_ui_root.add_child(library_layer)
    play_hud = Control.new(); play_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); play_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; host_ui_root.add_child(play_hud)
    chat_overlay = Control.new(); chat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); chat_overlay.visible = false; chat_overlay.process_mode = Node.PROCESS_MODE_ALWAYS; chat_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; host_ui_root.add_child(chat_overlay)
    _build_library()
    _build_play_hud()
    _build_chat()
    _build_dialogs()
    host_ui_root.move_child(toast_label, host_ui_root.get_child_count() - 1)

func _build_library() -> void:
    WorkspaceUIScript.build_library(self)

func _build_play_hud() -> void:
    WorkspaceUIScript.build_play_hud(self)

func _build_chat() -> void:
    WorkspaceUIScript.build_chat(self)

func _add_reload_button(parent: Control) -> void:
    var button = Button.new()
    button.text = "Reload Game"
    button.tooltip_text = "Reload the workspace when the agent is idle"
    button.pressed.connect(_reload_game)
    parent.add_child(button)
    reload_game_buttons.append(button)

func _add_execution_status(parent: Control) -> Label:
    var label = Label.new()
    label.text = "Not running"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_color_override("font_color", ThemeFactoryScript.MUTED)
    parent.add_child(label)
    execution_status_labels.append(label)
    return label

func _has_runnable_game() -> bool:
    return current_game != "" and (FileAccess.file_exists(store.game_path(current_game).path_join("main.gd")) or store.has_working_snapshot(current_game))

func _update_execution_status() -> void:
    var text = "Not running"
    if is_instance_valid(runner) and runner.has_active_game():
        text = running_source_status
    for label in execution_status_labels:
        label.text = text
        label.add_theme_color_override("font_color", ThemeFactoryScript.ACCENT if text == "Running workspace" else Color("eac491") if text == "Running last working snapshot" else ThemeFactoryScript.MUTED)
    workspace_welcome.visible = not is_instance_valid(runner) or not runner.has_active_game()

func _run_game() -> void:
    if not is_instance_valid(runner) or runner.has_active_game() or (is_instance_valid(agent) and agent.busy):
        return
    if not _has_runnable_game():
        _set_chat_busy_controls(false)
        _toast("No game to run yet. Ask the agent to create main.gd.")
        return
    var result: Dictionary = runner.load_game(store.game_path(current_game))
    if not result.ok and not runner.has_active_game() and store.has_working_snapshot(current_game):
        result = runner.load_game(metadata.snapshot_dir(current_game))
        if result.ok:
            _toast("Workspace candidate is broken; launched the last working snapshot.")
    _set_chat_busy_controls(false)
    if result.ok:
        _set_chat_visible(false)

func _reload_game() -> void:
    if not is_instance_valid(runner) or not runner.has_active_game() or (is_instance_valid(agent) and agent.busy):
        return
    runner.load_game(store.game_path(current_game))
    _set_chat_busy_controls(false)

func _reload_approval_changed(pending: bool) -> void:
    reload_notice.visible = pending
    approve_reload_button.visible = pending
    approve_reload_button.disabled = not pending

func _approve_agent_reload() -> void:
    if is_instance_valid(agent) and agent.has_method("approve_reload"):
        agent.approve_reload()

func _build_dialogs() -> void:
    _build_new_game_overlay()
    SettingsUIScript.build_management(self)
    _build_settings_overlay()

func _build_new_game_overlay() -> void:
    SettingsUIScript.build_new_game(self)

func _open_new_game() -> void:
    name_edit.text = ""
    new_game_dialog.visible = true
    name_edit.grab_focus()

func _build_settings_overlay() -> void:
    SettingsUIScript.build(self)

func _refresh_library() -> void:
    WorkspaceUIScript.refresh_library(self)

func _show_library() -> void:
    _reload_approval_changed(false)
    current_game = ""
    generated_input_states.clear()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    if is_instance_valid(runner):
        runner.runtime_log.close()
        runner.queue_free()
    runner = null
    if is_instance_valid(agent):
        remove_child(agent)
        agent.queue_free()
    agent = null
    if game_edit_guard != null: game_edit_guard.release()
    game_edit_guard = null
    get_tree().paused = false
    background.visible = true
    library_layer.visible = true; play_hud.visible = false; chat_overlay.visible = false
    _refresh_library()

func _create_game() -> void:
    var result = store.create_game(name_edit.text, str(harness_option.get_item_metadata(harness_option.selected)))
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
    game_title_label.tooltip_text = name
    workspace_title_label.text = name
    workspace_title_label.tooltip_text = name
    status_label.text = "Ready"
    game_edit_guard = preload("res://src/core/game_edit_guard.gd").new()
    game_edit_guard.workspace = store.game_path(name)
    var editable = game_edit_guard.acquire()
    var git_state = store.ensure_game_repo(name) if editable else {"ok": true}
    if not bool(git_state.get("ok", false)):
        AppLoggerScript.game_event(name, "git.recovery_failed", "code=%s output=%s" % [str(git_state.get("code", "")), str(git_state.get("output", "")).left(1000)], "WARN")
    elif bool(git_state.get("recovered", false)):
        AppLoggerScript.game_event(name, "git.recovered", "missing Git metadata was recreated and current workspace captured as baseline", "WARN")
    runner = GameRunnerScript.new(); runner.name = "GeneratedGameRunner"; runner.process_mode = Node.PROCESS_MODE_PAUSABLE; add_child(runner); move_child(runner, 2)
    runner.runtime_log.start(name, store.game_path(name))
    runner.load_succeeded.connect(_on_load_success)
    runner.load_failed.connect(func(msg): AppLoggerScript.game_event(name, "game.load_failed", str(msg), "ERROR"); _handle_load_failure(str(msg)))
    tools = GameToolsScript.new(store.game_path(name), runner)
    _attach_game_agent()
    _load_transcript()
    _set_chat_visible(true)
    _set_chat_busy_controls(false)
    if not editable:
        status_label.text = game_edit_guard.error
        _append_chat("system", game_edit_guard.error)
    if not FileAccess.file_exists(store.game_path(name).path_join("main.gd")):
        _append_chat("system", "This workspace is empty. Tell the agent what game to build.")

func _attach_game_agent() -> void:
    match str(metadata.read_game(current_game).get("harness", "pi")):
        "command-code": agent = CommandCodeAgentControllerScript.new()
        "opencode": agent = OpenCodeAgentControllerScript.new()
        "codex": agent = CodexAgentControllerScript.new()
        "cline": agent = ClineAgentControllerScript.new()
        "cursor": agent = CursorAgentControllerScript.new()
        "grok-build": agent = GrokBuildAgentControllerScript.new()
        "agy": agent = AgyAgentControllerScript.new()
        "kimi": agent = KimiAgentControllerScript.new()
        _: agent = PiAgentControllerScript.new()
    add_child(agent)
    agent.editor_guard = game_edit_guard
    agent.configure(current_game, tools)
    agent.status_changed.connect(func(text): status_label.text = text)
    agent.assistant_message.connect(func(text): _append_chat("assistant", text))
    agent.llm_snippet.connect(func(kind, text): _append_chat(kind, text))
    if agent.has_signal("llm_stream_delta"):
        agent.llm_stream_delta.connect(_append_stream_delta)
    if agent.has_signal("llm_stream_end"):
        agent.llm_stream_end.connect(_end_stream_block)
    if agent.has_signal("transcript_reconciled"):
        agent.transcript_reconciled.connect(_load_transcript)
    agent.finished.connect(_on_agent_finished)
    agent.reload_approval_changed.connect(_reload_approval_changed)

func _finish_settings_save() -> void:
    if current_game != "":
        var selected = str(game_harness_option.get_item_metadata(game_harness_option.selected))
        var game_meta = metadata.read_game(current_game)
        if selected != str(game_meta.get("harness", "pi")):
            game_meta.harness = selected
            if not metadata.write_game(current_game, game_meta):
                _toast("Could not save the game harness. Try again after fixing storage access.")
                return
            if is_instance_valid(agent):
                agent.editor_guard = null # Transfer ownership without releasing it.
                remove_child(agent) # _exit_tree closes the old backend before replacement.
                agent.queue_free()
            _end_stream_block("")
            _reload_approval_changed(false)
            _attach_game_agent()
            status_label.text = "Ready"
            _set_chat_busy_controls(false)
            _append_chat("system", "Switched to %s. Game files and chat are shared; each harness keeps its own agent session." % game_harness_option.get_item_text(game_harness_option.selected))
    settings_dialog.visible = false
    _toast("Settings saved.")

func _handle_load_failure(message: String) -> void:
    if is_instance_valid(agent) and agent.busy:
        status_label.text = "Reload failed; agent is continuing repairs…"
        return
    _toast(message)

func _on_load_success(_version: int) -> void:
    if current_game != "":
        running_source_status = "Running workspace" if runner.active_source_path == store.game_path(current_game).path_join("main.gd") else "Running last working snapshot"
        _reserve_host_canvas_layers()
        # A fallback load must preserve the snapshot that rescued this game.
        if runner.active_source_path == store.game_path(current_game).path_join("main.gd"):
            if game_edit_guard != null and game_edit_guard.acquire() and not store.save_working_snapshot(current_game):
                AppLoggerScript.game_event(current_game, "snapshot.failed", "Could not save the working snapshot.", "WARN")
                _append_chat("system", "Game loaded, but its working snapshot could not be saved.")
        if chat_overlay.visible:
            # A freshly loaded game may capture the mouse or add full-screen Controls in _ready().
            # Remember its intended gameplay mouse mode, then reassert host-chat input ownership.
            gameplay_mouse_mode = Input.mouse_mode
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            _suspend_generated_input()
        AppLoggerScript.game_event(current_game, "game.reload", "load_version=%d ok=true" % _version)
        _toast("Game reloaded successfully.")
        _set_chat_busy_controls(is_instance_valid(agent) and agent.busy)

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
    if is_instance_valid(stop_button):
        stop_button.disabled = not is_busy
    if is_instance_valid(rename_button):
        rename_button.disabled = is_busy
    if is_instance_valid(run_game_button):
        run_game_button.disabled = is_busy or not is_instance_valid(runner) or runner.has_active_game() or not _has_runnable_game()
    if is_instance_valid(resume_game_button):
        resume_game_button.disabled = not is_instance_valid(runner) or not runner.has_active_game()
    for button in reload_game_buttons:
        button.disabled = is_busy or not is_instance_valid(runner) or not runner.has_active_game()
    _update_execution_status()
    if not is_busy and chat_overlay.visible and not settings_dialog.visible and is_instance_valid(chat_input):
        chat_input.grab_focus()

func _stop_agent() -> void:
    if is_instance_valid(agent) and agent.busy:
        agent.cancel()

func _append_chat(role: String, text: String) -> void:
    var label = {"user": "YOU", "assistant": "AGENT", "thinking": "THINK", "tool": "TOOL"}.get(role, "HOST")
    var color = {"user": "8bc7dd", "assistant": "b8e986", "thinking": "97a6ab", "tool": "ecc592"}.get(role, "8393b2")
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
        var color = {"assistant": "b8e986", "thinking": "97a6ab"}.get(kind, "c2f0cb")
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
        play_hud.visible = false
        get_tree().paused = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _suspend_generated_input()
        chat_input.grab_focus()
    else:
        if not is_instance_valid(runner) or not runner.has_active_game():
            return
        _restore_generated_input()
        chat_overlay.visible = false
        play_hud.visible = true
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
    if is_instance_valid(agent) and agent.busy:
        _toast("Stop the agent or wait for it to finish before renaming.")
        return
    rename_target = name if name != "" else current_game
    if rename_target == "": return
    rename_edit.text = rename_target
    rename_dialog.visible = true
    rename_edit.grab_focus()
    rename_edit.select_all()

func _rename_game() -> void:
    if is_instance_valid(agent) and agent.busy:
        _toast("Stop the agent or wait for it to finish before renaming.")
        return
    if tools != null and is_instance_valid(tools.test_supervisor) and tools.test_supervisor.has_running():
        tools.test_supervisor.stop_all()
        _toast("Stopping the separate test game. Rename again after it exits.")
        return
    var old = rename_target
    if old == "": return
    var edit_guard = game_edit_guard if current_game == old else preload("res://src/core/game_edit_guard.gd").new()
    edit_guard.workspace = store.game_path(old)
    if not edit_guard.acquire():
        _toast(edit_guard.error)
        return
    var destination_guard = preload("res://src/core/game_edit_guard.gd").new()
    destination_guard.workspace = store.game_path(PathUtils.sanitize_game_name(rename_edit.text))
    if destination_guard.workspace != edit_guard.workspace and not destination_guard.acquire():
        _toast(destination_guard.error)
        return
    if current_game == old:
        # Release Pi's cwd and session handles before moving their directories.
        agent.restart_runtime()
        runner.runtime_log.pause_writer()
    var result: Dictionary = store.rename_game(old, rename_edit.text)
    if not result.get("ok", false):
        if current_game == old:
            runner.runtime_log.rebind(old, store.game_path(old))
        _toast(str(result.get("error", "Rename failed.")))
        return
    var new_name = str(result.get("name", old))
    if current_game == old:
        if new_name != old:
            edit_guard.release()
            game_edit_guard = destination_guard
            agent.editor_guard = game_edit_guard
        current_game = new_name
        game_title_label.text = current_game
        game_title_label.tooltip_text = current_game
        workspace_title_label.text = current_game
        workspace_title_label.tooltip_text = current_game
        tools.workspace = store.game_path(current_game)
        if is_instance_valid(tools.test_supervisor):
            tools.test_supervisor.rebind(tools.workspace)
        runner.runtime_log.rebind(current_game, tools.workspace)
        agent.configure(current_game, tools)
    else:
        _refresh_library()
    rename_target = ""
    rename_dialog.visible = false
    _toast("Renamed to %s." % new_name)

func _ask_delete(name: String) -> void:
    pending_delete = name
    delete_game_label.text = name
    delete_dialog.visible = true

func _delete_game_confirmed() -> void:
    if pending_delete == "": return
    var target = pending_delete
    if current_game == target and is_instance_valid(agent) and agent.busy:
        _toast("Stop the agent before deleting its game.")
        return
    var edit_guard = game_edit_guard if current_game == target else preload("res://src/core/game_edit_guard.gd").new()
    edit_guard.workspace = store.game_path(target)
    if not edit_guard.acquire():
        _toast(edit_guard.error)
        return
    pending_delete = ""
    delete_dialog.visible = false
    if current_game == target:
        if is_instance_valid(runner):
            runner.runtime_log.close()
        current_game = ""
    if not store.delete_game(target):
        _toast("Could not delete the game. Close programs using its files and try again.")
    _show_library()

func _request_new_codex_session() -> void:
    if current_game == "" or not is_instance_valid(agent) or agent.busy or metadata.read_game(current_game).get("harness") not in ["codex", "cline", "cursor", "grok-build", "agy", "kimi"]:
        return
    native_session_title.text = "Start a new %s session?" % _native_harness_label()
    native_session_description.text = "The next message starts a fresh %s conversation. The previous session reference is archived, and your chat and game files are kept. The old conversation will not be included in the new agent context." % _native_harness_label()
    codex_session_game = current_game
    codex_session_dialog.move_to_front()
    codex_session_dialog.visible = true

func _cancel_new_codex_session() -> void:
    codex_session_game = ""
    codex_session_dialog.visible = false

func _confirm_new_codex_session() -> void:
    if codex_session_game == "" or codex_session_game != current_game or not is_instance_valid(agent) or agent.busy or metadata.read_game(current_game).get("harness") not in ["codex", "cline", "cursor", "grok-build", "agy", "kimi"]:
        _cancel_new_codex_session()
        return
    var result = agent.start_new_session()
    _cancel_new_codex_session()
    if not result.get("ok", false):
        _toast(str(result.get("error", "Could not start a new native session.")))
        return
    _append_chat("system", "A new %s session will start with your next message. The previous session reference, chat and game files were kept." % _native_harness_label())
    _close_settings()

func _open_settings() -> void:
    game_harness_option.disabled = current_game == "" or (is_instance_valid(agent) and agent.busy)
    var saved_harness = str(metadata.read_game(current_game).get("harness", "pi")) if current_game != "" else "pi"
    codex_new_session_button.visible = current_game != "" and saved_harness in ["codex", "cline", "cursor", "grok-build", "agy", "kimi"]
    codex_new_session_button.text = "Start new %s session" % _native_harness_label()
    codex_new_session_button.disabled = not is_instance_valid(agent) or agent.busy
    for i in game_harness_option.item_count:
        if str(game_harness_option.get_item_metadata(i)) == saved_harness:
            game_harness_option.select(i)
    var settings = metadata.global_settings()
    var creds = metadata.credentials()
    var id = str(settings.get("provider", "openrouter"))
    _select_provider_id(id)
    model_edit.text = str(settings.get("model", PiProviderCatalogScript.defaults().get(id, "")))
    key_edit.text = str(creds.get(id, ""))
    custom_base_edit.text = str(settings.get("custom_base_url", ""))
    custom_base_edit.get_parent().visible = id == "custom"
    _select_reasoning_effort(str(settings.get("reasoning_effort", "")))
    agent_steps_spin.value = clampi(int(settings.get("max_agent_steps", PiAgentControllerScript.DEFAULT_MAX_STEPS)), PiAgentControllerScript.MIN_AGENT_STEPS, PiAgentControllerScript.MAX_AGENT_STEPS)
    llm_delay_spin.value = clampf(float(settings.get("llm_call_delay_sec", PiAgentControllerScript.DEFAULT_LLM_CALL_DELAY_SEC)), PiAgentControllerScript.MIN_LLM_CALL_DELAY_SEC, PiAgentControllerScript.MAX_LLM_CALL_DELAY_SEC)
    compaction_auto_spin.value = clampi(int(settings.get("compaction_auto_tokens", 100000)), 0, 2000000)
    compaction_keep_spin.value = clampi(int(settings.get("compaction_keep_recent_tokens", 20000)), 1000, 500000)
    rendered_tests_check.button_pressed = bool(settings.get("allow_rendered_tests", false))
    auto_reload_check.button_pressed = bool(settings.get("auto_approve_reloads", false))
    if current_game != "":
        var game_meta = metadata.read_game(current_game)
        _select_game_provider_id(str(game_meta.get("provider_override", "")))
        game_override_model.text = str(game_meta.get("model_override", ""))
        game_override_provider.disabled = false
        game_override_model.editable = true
        var estimated = agent.context_tokens() if is_instance_valid(agent) and agent.has_method("context_tokens") else 0
        compaction_status_label.text = "Current context: ~%d tokens." % estimated if estimated > 0 else "Context size is available after the first provider response."
        compact_now_button.disabled = not is_instance_valid(agent) or agent.busy
    else:
        game_override_provider.select(0)
        game_override_model.text = ""
        game_override_provider.disabled = true
        game_override_model.editable = false
        compaction_status_label.text = "Open a game to compact its conversation manually."
        compact_now_button.disabled = true
    var native_settings = _uses_native_agent_settings()
    provider_option.disabled = native_settings
    reasoning_option.disabled = native_settings
    model_edit.editable = not native_settings
    key_edit.editable = not native_settings
    custom_base_edit.editable = not native_settings
    agent_steps_spin.editable = not native_settings
    llm_delay_spin.editable = not native_settings
    compaction_auto_spin.editable = not _uses_native_compaction()
    compaction_keep_spin.editable = not native_settings
    if _uses_native_compaction():
        compact_now_button.disabled = true
        compaction_status_label.text = _native_harness_label() + " manages its own compaction, model, and provider settings."
        if _native_harness_label() == "Cursor":
            compaction_status_label.text += " Cursor uses Auto. The model selected in the editor or interactive CLI is not inherited."
        if _native_harness_label() == "AGY":
            compaction_status_label.text += " Experimental: live model execution has not been verified."
    if native_settings:
        game_override_provider.disabled = true
        game_override_model.editable = false
        if _uses_command_code():
            compaction_status_label.text += " GameSmith's threshold triggers native Command-code compaction between requests. Retained context, model, and provider settings belong to Command-code."
    settings_dialog.move_to_front()
    settings_dialog.visible = true

func _uses_command_code() -> bool:
    return current_game != "" and metadata.read_game(current_game).get("harness", "pi") == "command-code"

func _uses_opencode() -> bool:
    return current_game != "" and metadata.read_game(current_game).get("harness", "pi") == "opencode"

func _uses_native_agent_settings() -> bool:
    return _uses_command_code() or _uses_native_compaction()

func _uses_native_compaction() -> bool:
    return current_game != "" and metadata.read_game(current_game).get("harness", "pi") in ["opencode", "codex", "cline", "cursor", "grok-build", "agy", "kimi"]

func _native_harness_label() -> String:
    return {"codex": "Codex", "cline": "Cline", "cursor": "Cursor", "grok-build": "Grok Build", "agy": "AGY", "kimi": "Kimi", "opencode": "OpenCode"}.get(metadata.read_game(current_game).get("harness", "pi"), "OpenCode")

func _close_settings() -> void:
    _cancel_new_codex_session()
    settings_dialog.visible = false
    if chat_overlay.visible and chat_input.editable:
        chat_input.grab_focus()

func _compact_now_from_settings() -> void:
    if _uses_native_compaction():
        compaction_status_label.text = _native_harness_label() + " manages its own compaction."
        return
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
    if not is_inside_tree():
        return
    var chat_result = ""
    if bool(result.get("ok", false)):
        chat_result = "Compaction finished: ~%d estimated tokens before; %s after." % [int(result.get("tokens_before", 0)), "unknown" if result.get("tokens_after") == null else "~%d" % int(result.tokens_after)]
        compaction_status_label.text = chat_result
    elif bool(result.get("no_op", false)):
        chat_result = "Compaction skipped: " + str(result.get("error", "Nothing to compact."))
        compaction_status_label.text = chat_result
    elif bool(result.get("cancelled", false)):
        chat_result = "Compaction cancelled."
        compaction_status_label.text = chat_result
    else:
        chat_result = "Compaction failed: " + str(result.get("error", "Unknown error."))
        compaction_status_label.text = chat_result

    _append_chat("system", chat_result)
    compact_now_button.disabled = false
    _set_chat_busy_controls(is_instance_valid(agent) and agent.busy)


func _provider_changed(index: int) -> void:
    if _uses_native_agent_settings():
        return
    var id = str(provider_option.get_item_metadata(index)); var settings = metadata.global_settings(); var creds = metadata.credentials()
    model_edit.text = str(PiProviderCatalogScript.defaults().get(id, settings.get("model", "")))
    key_edit.text = str(creds.get(id, ""))
    custom_base_edit.get_parent().visible = id == "custom"

func _save_settings() -> void:
    if current_game != "" and not game_edit_guard.acquire():
        _toast(game_edit_guard.error)
        return
    if current_game != "" and is_instance_valid(agent) and agent.busy:
        if str(game_harness_option.get_item_metadata(game_harness_option.selected)) != str(metadata.read_game(current_game).get("harness", "pi")):
            _toast("Wait for the agent to finish or stop it before switching harnesses.")
            return
    if _uses_native_agent_settings():
        var host_settings = metadata.global_settings()
        if _uses_command_code():
            host_settings.compaction_auto_tokens = int(compaction_auto_spin.value)
        host_settings.allow_rendered_tests = rendered_tests_check.button_pressed
        host_settings.auto_approve_reloads = auto_reload_check.button_pressed
        if not metadata.save_global_settings(host_settings):
            _toast("Could not save host settings.")
            return
        _finish_settings_save()
        return
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
    settings.allow_rendered_tests = rendered_tests_check.button_pressed
    settings.auto_approve_reloads = auto_reload_check.button_pressed
    var failures: Array[String] = []
    if not metadata.save_global_settings(settings):
        failures.append("global settings")
    AppLoggerScript.global_event("settings.save", "provider=%s model=%s reasoning_effort=%s max_agent_steps=%d llm_call_delay_sec=%.1f compaction_auto_tokens=%d compaction_keep_recent_tokens=%d" % [id, settings.model, settings.reasoning_effort, int(settings.max_agent_steps), float(settings.llm_call_delay_sec), int(settings.compaction_auto_tokens), int(settings.compaction_keep_recent_tokens)])
    var creds = metadata.credentials()
    creds[id] = key_edit.text.strip_edges()
    if not metadata.save_credentials(creds):
        failures.append("provider credentials")
    if current_game != "":
        var game_meta = metadata.read_game(current_game)
        game_meta.provider_override = str(game_override_provider.get_item_metadata(game_override_provider.selected))
        game_meta.model_override = game_override_model.text.strip_edges()
        if not metadata.write_game(current_game, game_meta):
            failures.append("game settings")
        if is_instance_valid(agent) and agent.has_method("settings_changed"):
            agent.settings_changed()
    if not failures.is_empty():
        var message = "Could not save %s. Some other changes may have been saved; retry after fixing storage access." % ", ".join(failures)
        AppLoggerScript.global_event("settings.save_failed", message, "ERROR")
        compaction_status_label.text = message
        _toast(message)
        return
    _finish_settings_save()

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
    toast_label.visible = true
    var token = Time.get_ticks_msec(); toast_label.set_meta("toast_token", token)
    await get_tree().create_timer(4.0, true).timeout
    if toast_label.get_meta("toast_token", -1) == token:
        toast_label.text = ""
        toast_label.visible = false

func _maybe_capture() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture="):
            var path = arg.trim_prefix("--capture=")
            await get_tree().process_frame; await get_tree().process_frame; await get_tree().process_frame
            get_viewport().get_texture().get_image().save_png(path)
            get_tree().quit()
