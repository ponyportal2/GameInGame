import { test } from "node:test";
import assert from "node:assert/strict";
import { modelCapabilities, UNKNOWN_CAPABILITIES } from "../tools/pi/model-capabilities.mjs";

test("exact provider catalog metadata is retained", () => {
  const known = { reasoning: true, contextWindow: 123456, maxTokens: 1234, input: ["text"], thinkingLevelMap: { max: null } };
  assert.deepEqual(modelCapabilities("openrouter", "known", (provider, id) => {
    assert.equal(provider, "openrouter");
    assert.equal(id, "known");
    return known;
  }), known);
});

test("unknown/custom models never inherit guessed capabilities", () => {
  assert.deepEqual(modelCapabilities("openrouter", "unknown", () => undefined), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("openrouter", "unknown", () => { throw new Error("missing"); }), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("custom", "known-upstream-name", () => { throw new Error("must not look up custom endpoints"); }), UNKNOWN_CAPABILITIES);
  assert.deepEqual(modelCapabilities("openrouter", "invalid", () => ({ contextWindow: 0, maxTokens: 42 })), UNKNOWN_CAPABILITIES);
});
