export const UNKNOWN_CAPABILITIES = Object.freeze({ reasoning: false, contextWindow: 8192, maxTokens: 1024 });

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
