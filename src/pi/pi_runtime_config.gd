class_name PiRuntimeConfig
extends RefCounted

const MetadataStoreScript = preload("res://src/core/metadata_store.gd")
const JsonStoreScript = preload("res://src/core/json_store.gd")
const PiProviderCatalogScript = preload("res://src/pi/pi_provider_catalog.gd")

const PI_PROVIDER_ID = "gamesmith"
# Pi requires numeric limits for custom model definitions. These are conservative
# budgets for unknown models, not claims about provider capabilities.
const UNKNOWN_CONTEXT_BUDGET = 8192
const UNKNOWN_OUTPUT_BUDGET = 1024

static func prepare(game_name: String, workspace: String, settings: Dictionary, credentials: Dictionary, game_meta: Dictionary) -> Dictionary:
    var metadata = MetadataStoreScript.new()
    var root = metadata.game_meta_dir(game_name).path_join("pi")
    var agent_dir = root.path_join("agent")
    var session_dir = root.path_join("sessions")
    var bridge_dir = root.path_join("bridge")
    for dir in [root, agent_dir, session_dir, bridge_dir]:
        var err = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
        if err != OK and err != ERR_ALREADY_EXISTS:
            return {"ok": false, "error": "Could not create Pi runtime directory: " + dir}

    var extension_source = FileAccess.get_file_as_string("res://tools/pi/gamesmith-extension.ts")
    if extension_source == "":
        return {"ok": false, "error": "Bundled GameSmith Pi extension is missing."}
    var extension_path = agent_dir.path_join("gamesmith-extension.ts")
    var extension_file = FileAccess.open(extension_path, FileAccess.WRITE)
    if extension_file == null:
        return {"ok": false, "error": "Could not write Pi extension."}
    extension_file.store_string(extension_source)
    extension_file.close()

    for module in ["workspace-paths.mjs", "model-capabilities.mjs"]:
        var module_source = FileAccess.get_file_as_string("res://tools/pi/" + module)
        var module_file = FileAccess.open(agent_dir.path_join(module), FileAccess.WRITE)
        if module_source == "" or module_file == null:
            return {"ok": false, "error": "Could not prepare Pi module: " + module}
        module_file.store_string(module_source)
        module_file.close()

    var prompt_file = FileAccess.open(agent_dir.path_join("APPEND_SYSTEM.md"), FileAccess.WRITE)
    if prompt_file == null:
        return {"ok": false, "error": "Could not write Pi GameSmith prompt."}
    prompt_file.store_string(_game_prompt())
    prompt_file.close()

    var provider_id = str(game_meta.get("provider_override", ""))
    var model = str(game_meta.get("model_override", ""))
    if provider_id == "":
        provider_id = str(settings.get("provider", "openrouter"))
    if model == "":
        model = str(settings.get("model", PiProviderCatalogScript.defaults().get(provider_id, "")))
    if model.strip_edges() == "":
        return {"ok": false, "error": "No model configured."}

    var base_url = PiProviderCatalogScript.base_url(provider_id, settings)
    var subscription_mode = PiProviderCatalogScript.uses_global_auth(provider_id)
    if base_url == "" and not subscription_mode:
        return {"ok": false, "error": "Provider endpoint is not configured."}

    var key = str(credentials.get(provider_id, ""))
    if not subscription_mode and PiProviderCatalogScript.requires_api_key(provider_id) and key.strip_edges() == "":
        return {"ok": false, "error": "No API key configured for %s." % provider_id}
    if not subscription_mode and key.strip_edges() == "":
        key = "gamesmith-local"

    var headers = {}
    match provider_id:
        "openrouter":
            headers["X-Title"] = "GameSmith"
        "opencode_go":
            headers["x-opencode-session"] = game_name
        _:
            pass

    var pi_provider = "openai-codex" if subscription_mode else PI_PROVIDER_ID
    var model_config = {"providers": {}}
    if not subscription_mode:
        var provider_config = {
            "baseUrl": base_url,
            "api": "openai-completions",
            "apiKey": "$GAMESMITH_PI_API_KEY",
            "models": [{
                "id": model,
                "name": model,
                "reasoning": false,
                "contextWindow": UNKNOWN_CONTEXT_BUDGET,
                "maxTokens": UNKNOWN_OUTPUT_BUDGET
            }]
        }
        if not headers.is_empty():
            provider_config["headers"] = headers
        model_config.providers[PI_PROVIDER_ID] = provider_config
    if not JsonStoreScript.write_dict(agent_dir.path_join("models.json"), model_config):
        return {"ok": false, "error": "Could not write Pi models.json."}

    var pi_settings = {
        "compaction": {
            "enabled": false,
            "keepRecentTokens": clampi(int(settings.get("compaction_keep_recent_tokens", 20000)), 1000, UNKNOWN_CONTEXT_BUDGET / 4) if not subscription_mode else maxi(1000, int(settings.get("compaction_keep_recent_tokens", 20000)))
        },
        "retry": {
            "enabled": true,
            "maxRetries": 3,
            "baseDelayMs": 2000
        },
        "showCacheMissNotices": false
    }
    if not JsonStoreScript.write_dict(agent_dir.path_join("settings.json"), pi_settings):
        return {"ok": false, "error": "Could not write Pi settings.json."}

    _clear_bridge(bridge_dir)
    return {
        "ok": true,
        "workspace": ProjectSettings.globalize_path(workspace),
        "agent_dir": ProjectSettings.globalize_path(agent_dir),
        "session_dir": ProjectSettings.globalize_path(session_dir),
        "bridge_dir": ProjectSettings.globalize_path(bridge_dir),
        "extension_path": ProjectSettings.globalize_path(extension_path),
        "prompt_path": ProjectSettings.globalize_path(agent_dir.path_join("APPEND_SYSTEM.md")),
        "legacy_transcript": ProjectSettings.globalize_path(metadata.transcript_path(game_name)),
        "provider": pi_provider,
        "source_provider": provider_id,
        "model": model,
        "api_key": key if not subscription_mode else "",
        "use_global_pi_auth": subscription_mode,
        "thinking": _pi_thinking(str(settings.get("reasoning_effort", ""))),
        "llm_delay_ms": maxi(0, int(round(float(settings.get("llm_call_delay_sec", 6.0)) * 1000.0))),
        "max_turns": clampi(int(settings.get("max_agent_steps", 150)), 1, 500)
    }

static func _pi_thinking(value: String) -> String:
    var effort = value.strip_edges().to_lower()
    if effort == "" or effort == "none":
        return "off" if effort == "none" else ""
    if effort in ["minimal", "low", "medium", "high", "xhigh", "max"]:
        return effort
    return ""

static func _clear_bridge(bridge_dir: String) -> void:
    var dir = DirAccess.open(bridge_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    var item = dir.get_next()
    while item != "":
        if not dir.current_is_dir() and (item.begins_with("request-") or item.begins_with("response-")):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(bridge_dir.path_join(item)))
        item = dir.get_next()
    dir.list_dir_end()

static func _game_prompt() -> String:
    return """You are the game-building agent inside GameSmith. The player expects you to act, not merely explain.

GameSmith-specific rules:
- The current working directory is the entire generated game workspace. Stay inside it.
- There is deliberately no shell/bash/PowerShell tool. Use Pi's read/edit/write/grep/find/ls plus the GameSmith tools.
- main.gd at workspace root is the generated game's entry point and must extend a Godot Node type.
- Generated games are GDScript-first and should build their scene tree from code. Do not create .tscn files or depend on imported images, models, sounds, or fonts unless the player explicitly supplied them.
- 2D and 3D are both allowed. Prefer engine primitives, procedural geometry, built-in drawing, and code-created shaders/materials.
- Before changing an existing game, inspect the relevant current files. Pi's read tool is bounded; continue with offset/limit when it reports truncation.
- Prefer Pi's exact edit tool for surgical edits. Use write only for a new file or an intentional complete rewrite.
- File edits never reload automatically. Call reload_game after the coherent edit set is ready to try.
- If reload_game fails, inspect files and read_runtime_log, fix the problem, and reload again in the same player request when reasonable.
- Use git_commit for coherent milestones, not every tiny edit.
- Never edit .git directly.
- Avoid dangerous global Godot mutations: do not quit the host tree, change host window mode, or write outside the workspace.
- For input, handle InputEventKey/InputEventMouseButton directly rather than modifying ProjectSettings input maps.
- A plain-text claim such as "Done" is not proof. GameSmith verifies creation/change/reload state at Pi's settlement boundary and may continue the run automatically.
- Finish with a concise player-facing summary after tool work.

GameSmith, not you, owns the running host UI, game library, session display, and Pi process lifecycle.
"""

