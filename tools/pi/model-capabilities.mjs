import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export const UNKNOWN_CAPABILITIES = Object.freeze({ reasoning: false, contextWindow: 8192, maxTokens: 1024 });

// Local summary budget, not a claim about model capacity. Pi spends 80% of
// reserveTokens on the history summary (50% on a split-turn summary).
export function compactionReserveTokens(model) {
  const context = Number.isFinite(model?.contextWindow) && model.contextWindow > 0 ? model.contextWindow : UNKNOWN_CAPABILITIES.contextWindow;
  return Math.max(1, Math.min(32768, Math.floor(context / 4)));
}
const METADATA_TTL_MS = 5 * 60 * 1000;
// A refresh outage must not turn yesterday's verified million-token model into
// an unknown 8K model. Bound offline reuse too; this is metadata, not a guarantee
// that a provider will never change its limits.
const OFFLINE_METADATA_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_CACHE_BYTES = 8 * 1024 * 1024;

async function modelListing(options) {
  const cachePath = options.cachePath;
  const now = (options.now ?? Date.now)();
  const ttl = options.ttlMs ?? METADATA_TTL_MS;
  let previous;
  if (cachePath) {
    try {
      if ((await stat(cachePath)).size <= MAX_CACHE_BYTES) {
        const cached = JSON.parse(await readFile(cachePath, "utf8"));
        if (cached.format === 1 && Number.isFinite(cached.fetchedAt) && now >= cached.fetchedAt && Array.isArray(cached.data)) {
          const age = now - cached.fetchedAt;
          if (age < ttl) return cached;
          if (age < OFFLINE_METADATA_MAX_AGE_MS) previous = cached;
        }
      }
    } catch { /* Missing, expired, or damaged cache: fetch public metadata. */ }
  }
  let listing;
  try {
    const response = await (options.fetch ?? fetch)("https://openrouter.ai/api/v1/models", { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error("Metadata discovery failed");
    listing = await response.json();
    if (!Array.isArray(listing.data) || !listing.data.length) throw new Error("Invalid metadata listing");
  } catch (error) {
    if (!previous) throw error;
    console.warn("GameSmith: OpenRouter metadata refresh failed; using previously verified capabilities (less than seven days old).");
    return previous;
  }
  // Cache only public capability fields, never request headers or credentials.
  const data = listing.data.filter((entry) => typeof entry.id === "string").map((entry) => ({
    id: entry.id, context_length: entry.context_length, top_provider: entry.top_provider,
    architecture: { input_modalities: entry.architecture?.input_modalities }, supported_parameters: entry.supported_parameters,
  }));
  const cached = { format: 1, fetchedAt: now, data };
  const bytes = JSON.stringify(cached);
  if (cachePath && Buffer.byteLength(bytes) <= MAX_CACHE_BYTES && data.length) {
    const temporary = `${cachePath}.${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.tmp`;
    try {
      await mkdir(dirname(cachePath), { recursive: true });
      await writeFile(temporary, bytes, "utf8");
      await rename(temporary, cachePath);
    } catch { /* A cache write failure must not prevent using live metadata. */ }
    finally { await rm(temporary, { force: true }).catch(() => {}); }
  }
  return cached;
}

// The bundled catalog cannot know newly published/stealth models. Fetch actual
// provider limits only for the official endpoint, never for a lookalike model
// name on a custom server. Metadata lookup is bounded; agent work is not.
export async function resolveModelCapabilities(provider, id, lookup, options = {}) {
  const officialOpenRouter = options.baseUrl?.replace(/\/$/, "") === "https://openrouter.ai/api/v1";
  const fallback = modelCapabilities(officialOpenRouter ? "openrouter" : provider, id, lookup);
  if (!officialOpenRouter) return fallback;
  try {
    const data = await modelListing(options);
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
