import { test } from "node:test";
import assert from "node:assert/strict";
import { modelCapabilities, resolveModelCapabilities, UNKNOWN_CAPABILITIES } from "../tools/pi/model-capabilities.mjs";

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
