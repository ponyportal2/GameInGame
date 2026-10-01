class_name PiProviderCatalog
extends RefCounted

const PROVIDERS := {
    "openrouter": {
        "display_name": "OpenRouter",
        "default_model": "openai/gpt-5.6",
        "base_url": "https://openrouter.ai/api/v1",
        "api_key_required": true,
        "global_auth": false
    },
    "opencode_go": {
        "display_name": "OpenCode Go",
        "default_model": "gpt-5.6-luna",
        "base_url": "https://opencode.ai/zen/go/v1",
        "api_key_required": true,
        "global_auth": false
    },
    "command_code": {
        "display_name": "Command Code",
        "default_model": "deepseek/deepseek-v4-flash",
        "base_url": "https://api.commandcode.ai/provider/v1",
        "api_key_required": true,
        "global_auth": false
    },
    "custom": {
        "display_name": "Custom OpenAI-compatible",
        "default_model": "",
        "base_url": "",
        "api_key_required": false,
        "global_auth": false
    },
    "openai_subscription": {
        "display_name": "OpenAI subscription (Pi global auth)",
        "default_model": "",
        "base_url": "",
        "api_key_required": false,
        "global_auth": true
    }
}

static func display_names() -> Dictionary:
    var out := {}
    for id in PROVIDERS:
        out[id] = str(PROVIDERS[id].display_name)
    return out

static func defaults() -> Dictionary:
    var out := {}
    for id in PROVIDERS:
        out[id] = str(PROVIDERS[id].default_model)
    return out

static func base_url(provider_id: String, settings: Dictionary) -> String:
    if provider_id == "custom":
        return custom_base_url(str(settings.get("custom_base_url", "")))
    if not PROVIDERS.has(provider_id):
        return ""
    return str(PROVIDERS[provider_id].base_url)

static func requires_api_key(provider_id: String) -> bool:
    return bool(PROVIDERS.get(provider_id, {}).get("api_key_required", false))

static func uses_global_auth(provider_id: String) -> bool:
    return bool(PROVIDERS.get(provider_id, {}).get("global_auth", false))

static func custom_base_url(raw: String) -> String:
    var base = raw.strip_edges()
    while base.ends_with("/"):
        base = base.left(base.length() - 1)
    if base.ends_with("/chat/completions"):
        base = base.left(base.length() - "/chat/completions".length())
    return base
