import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { modelCapabilities, resolveModelCapabilities, compactionReserveTokens, UNKNOWN_CAPABILITIES } from "../tools/pi/model-capabilities.mjs";

test("compaction budgets use discovered context capacity without inflating capabilities", () => {
  assert.equal(compactionReserveTokens(undefined), 2048);
  assert.equal(compactionReserveTokens({ contextWindow: 8192 }), 2048);
  const model = { contextWindow: 1000000, maxTokens: 524288 };
  assert.equal(compactionReserveTokens(model), 32768);
  assert.equal(Math.floor(compactionReserveTokens(model) * 0.8), 26214);
  assert.equal(compactionReserveTokens({ contextWindow: 32768 }), 8192);
  assert.deepEqual(model, { contextWindow: 1000000, maxTokens: 524288 });
});

test("public metadata cache is shared, expires, and never caches failed discovery", async () => {
  const root = await mkdtemp(join(tmpdir(), "gamesmith-model-cache-"));
  const cachePath = join(root, "models.json");
  let calls = 0;
  let now = 100000;
  let offline = false;
  const options = { baseUrl: "https://openrouter.ai/api/v1", cachePath, now: () => now, ttlMs: 1000,
    fetch: async () => {
      calls++;
      if (offline) throw new Error("offline");
      return { ok: true, json: async () => ({ data: [
        { id: "a", context_length: 10000, top_provider: { max_completion_tokens: 2000 } },
        { id: "b", context_length: 20000, top_provider: { max_completion_tokens: 3000 } },
      ] }) };
    } };
  try {
    assert.equal((await resolveModelCapabilities("custom", "a", () => undefined, options)).contextWindow, 10000);
    assert.equal((await resolveModelCapabilities("custom", "b", () => undefined, options)).contextWindow, 20000);
    assert.equal(calls, 1, "another game/model reuses the public listing");
    const saved = await readFile(cachePath, "utf8");
    now += 1001;
    offline = true;
    assert.equal((await resolveModelCapabilities("custom", "a", () => undefined, options)).contextWindow, 10000,
      "a failed refresh retains recently verified limits instead of shrinking the model to 8K/1K");
    assert.equal(await readFile(cachePath, "utf8"), saved, "failure never replaces successful metadata");
    offline = false;
    await resolveModelCapabilities("custom", "a", () => undefined, options);
    assert.equal(calls, 3);
    await writeFile(cachePath, "{broken");
    await resolveModelCapabilities("custom", "a", () => undefined, options);
    assert.equal(calls, 4, "damaged cache refetches");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("offline discovery only reuses recent valid metadata", async () => {
  const root = await mkdtemp(join(tmpdir(), "gamesmith-model-offline-"));
  const cachePath = join(root, "models.json");
  const now = 10 * 24 * 60 * 60 * 1000;
  const options = { baseUrl: "https://openrouter.ai/api/v1", cachePath, now: () => now,
    fetch: async () => { throw new Error("offline"); } };
  try {
    for (const fetchedAt of [0, now + 1]) {
      await writeFile(cachePath, JSON.stringify({ format: 1, fetchedAt, data: [
        { id: "a", context_length: 1000000, top_provider: { max_completion_tokens: 65536 } },
      ] }));
      assert.deepEqual(await resolveModelCapabilities("custom", "a", () => undefined, options), UNKNOWN_CAPABILITIES);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("custom official OpenRouter uses its catalog when metadata discovery fails", async () => {
  const known = { reasoning: true, contextWindow: 1000000, maxTokens: 65536 };
  assert.deepEqual(await resolveModelCapabilities("custom", "nvidia/nemotron-3-ultra-550b-a55b:free", (provider) => {
    assert.equal(provider, "openrouter");
    return known;
  }, { baseUrl: "https://openrouter.ai/api/v1", fetch: async () => { throw new Error("offline"); } }), known);
});

test("exact provider catalog metadata is retained", () => {
  const known = { reasoning: true, contextWindow: 123456, maxTokens: 1234, input: ["text"], thinkingLevelMap: { max: null } };
  assert.deepEqual(modelCapabilities("openrouter", "known", (provider, id) => {
    assert.equal(provider, "openrouter");
    assert.equal(id, "known");
    return known;
  }), known);
});

test("OpenRouter live metadata resolves models absent from Pi's catalog", async () => {
  const result = await resolveModelCapabilities("openrouter", "stealth/space-bunny-alpha", () => undefined, {
    baseUrl: "https://openrouter.ai/api/v1",
    fetch: async (url) => {
      assert.equal(url, "https://openrouter.ai/api/v1/models");
      return { ok: true, json: async () => ({ data: [{ id: "stealth/space-bunny-alpha", context_length: 1000000,
        top_provider: { max_completion_tokens: 524288 }, architecture: { input_modalities: ["text", "image", "video"] },
        supported_parameters: ["reasoning", "max_tokens"] }] }) };
    },
  });
  assert.equal(result.contextWindow, 1000000);
  assert.equal(result.maxTokens, 524288);
  assert.equal(result.reasoning, true);
  assert.deepEqual(result.input, ["text", "image"]);
});

test("metadata failures or incomplete limits retain conservative catalog fallback", async () => {
  for (const fetch of [async () => { throw new Error("offline"); }, async () => ({ ok: false }),
    async () => ({ ok: true, json: async () => ({ data: [{ id: "unknown", context_length: 1000000 }] }) })]) {
    assert.deepEqual(await resolveModelCapabilities("openrouter", "unknown", () => undefined,
      { baseUrl: "https://openrouter.ai/api/v1", fetch }), UNKNOWN_CAPABILITIES);
  }
});

test("Custom configuration pointing at official OpenRouter gets actual metadata too", async () => {
  const result = await resolveModelCapabilities("custom", "new-model", () => undefined, {
    baseUrl: "https://openrouter.ai/api/v1/", fetch: async () => ({ ok: true, json: async () => ({ data: [
      { id: "new-model", context_length: 1000000, top_provider: { max_completion_tokens: 524288 } },
    ] }) }),
  });
  assert.equal(result.contextWindow, 1000000);
  assert.equal(result.maxTokens, 524288);
});

test("custom endpoints never inherit OpenRouter metadata", async () => {
  for (const [provider, baseUrl] of [["custom", "https://example.test/v1"], ["openrouter", "http://localhost/v1"]]) {
    assert.deepEqual(await resolveModelCapabilities(provider, "unknown", () => undefined,
      { baseUrl, fetch: () => { assert.fail("must not fetch"); } }), UNKNOWN_CAPABILITIES);
  }
});

test("unknown/custom models never inherit guessed capabilities", () => {
  assert.deepEqual(modelCapabilities("openrouter", "unknown", () => undefined), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("openrouter", "unknown", () => { throw new Error("missing"); }), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("custom", "known-upstream-name", () => { throw new Error("must not look up custom endpoints"); }), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("openrouter", "invalid", () => ({ contextWindow: 0, maxTokens: 42 })), UNKNOWN_CAPABILITIES);
});
