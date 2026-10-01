class_name ProviderFactory
extends RefCounted

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
const OPENCODE_URL = "https://opencode.ai/zen/go/v1/chat/completions"
const COMMAND_URL = "https://api.commandcode.ai/provider/v1/chat/completions"

static func display_names() -> Dictionary:
    return {
        "openrouter": "OpenRouter",
        "opencode_go": "OpenCode Go",
        "command_code": "Command Code",
        "custom": "Custom OpenAI-compatible",
        "openai_subscription": "OpenAI subscription (adapter seam)"
    }

static func defaults() -> Dictionary:
    return {
        "openrouter": "openai/gpt-5.6",
        "opencode_go": "gpt-5.6-luna",
        "command_code": "deepseek/deepseek-v4-flash",
        "custom": "",
        "openai_subscription": ""
    }

static func make(owner: Node, provider_id: String, model: String, credentials: Dictionary, session_id: String, settings: Dictionary = {}) -> Variant:
    var key = str(credentials.get(provider_id, ""))
    var effort = str(settings.get("reasoning_effort", ""))
    match provider_id:
        "openrouter":
            return OpenAICompatibleProvider.new(owner, OPENROUTER_URL, key, model, PackedStringArray(["X-Title: GameSmith Host"]), effort)
        "opencode_go":
            return OpenAICompatibleProvider.new(owner, OPENCODE_URL, key, model, PackedStringArray(["User-Agent: gamesmith-host/0.1", "x-opencode-session: " + session_id]), effort)
        "command_code":
            return OpenAICompatibleProvider.new(owner, COMMAND_URL, key, model, PackedStringArray(["User-Agent: gamesmith-host/0.1"]), effort)
        "custom":
            var endpoint = custom_chat_endpoint(str(settings.get("custom_base_url", "")))
            if endpoint == "":
                return null
            return OpenAICompatibleProvider.new(owner, endpoint, key, model, PackedStringArray(["User-Agent: gamesmith-host/0.1"]), effort, false)
        "openai_subscription":
            return null
    return null

static func custom_chat_endpoint(base_url: String) -> String:
    var base = base_url.strip_edges()
    while base.ends_with("/"):
        base = base.left(base.length() - 1)
    if base == "":
        return ""
    if base.ends_with("/chat/completions"):
        return base
    if base.ends_with("/v1"):
        return base + "/chat/completions"
    return base + "/v1/chat/completions"

static func unavailable_reason(provider_id: String) -> String:
    if provider_id == "openai_subscription":
        return "OpenAI subscription sign-in is intentionally left behind the provider seam in this build; current ChatGPT subscription access is exposed through Codex CLI/OAuth rather than a simple embeddable API endpoint."
    if provider_id == "custom":
        return "Custom provider requires a /v1 base address in Provider settings."
    return "Provider adapter unavailable."
