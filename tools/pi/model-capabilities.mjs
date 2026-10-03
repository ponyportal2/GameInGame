export const UNKNOWN_CAPABILITIES = Object.freeze({ reasoning: false, contextWindow: 8192, maxTokens: 1024 });

// The bundled catalog cannot know newly published/stealth models. Fetch actual
// provider limits only for the official endpoint, never for a lookalike model
// name on a custom server. Metadata lookup is bounded; agent work is not.
export async function resolveModelCapabilities(provider, id, lookup, options = {}) {
  const fallback = modelCapabilities(provider, id, lookup);
  if (options.baseUrl?.replace(/\/$/, "") !== "https://openrouter.ai/api/v1") return fallback;
  try {
    const response = await (options.fetch ?? fetch)("https://openrouter.ai/api/v1/models", { signal: AbortSignal.timeout(10000) });
    if (!response.ok) return fallback;
    const data = await response.json();
    const model = data.data?.find((entry) => entry.id === id);
    const contextWindow = model?.top_provider?.context_length ?? model?.context_length;
    const maxTokens = model?.top_provider?.max_completion_tokens;
    if (!Number.isFinite(contextWindow) || contextWindow <= 0 || !Number.isFinite(maxTokens) || maxTokens <= 0) return fallback;
    const result = { ...fallback, contextWindow, maxTokens,
      reasoning: model.supported_parameters?.some((parameter) => ["reasoning", "reasoning_effort"].includes(parameter)) ?? false };
    if (Array.isArray(model.architecture?.input_modalities)) {
      result.input = model.architecture.input_modalities.filter((input) => ["text", "image"].includes(input));
    }
    return result;
  } catch {
    return fallback;
  }
}

// Match provider and model exactly. A name on an arbitrary local/custom endpoint
// does not establish that it has the capabilities of the upstream model.
export function modelCapabilities(provider, id, lookup) {
  const catalogProvider = { openrouter: "openrouter", opencode_go: "opencode-go", command_code: "command-code" }[provider];
  let known;
  if (catalogProvider) {
    try { known = lookup(catalogProvider, id); } catch { /* Absent from this Pi catalog. */ }
  }
  if (!known || !Number.isFinite(known.contextWindow) || known.contextWindow <= 0 || !Number.isFinite(known.maxTokens) || known.maxTokens <= 0) {
    return { ...UNKNOWN_CAPABILITIES };
  }
  const result = { reasoning: known.reasoning === true, contextWindow: known.contextWindow, maxTokens: known.maxTokens };
  for (const key of ["input", "cost", "thinkingLevelMap"]) {
    if (known[key] !== undefined) result[key] = known[key];
  }
  return result;
}
