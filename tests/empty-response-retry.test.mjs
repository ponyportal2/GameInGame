import { test } from "node:test";
import assert from "node:assert/strict";
import { EmptyResponseRetry } from "../tools/pi/empty-response-retry.mjs";

function boundary(overrides = {}) {
  const completedTool = { role: "toolResult", content: [{ type: "text", text: "saved" }] };
  const message = { role: "assistant", stopReason: "error", errorMessage: "Provider returned an empty response", content: [], ...overrides };
  return { outcome: "error", entries: [], context: {
    contextMessages: [completedTool, message],
    contextEntries: [{ sourceEntry: { id: "tool" }, messages: [completedTool] },
      { sourceEntry: { id: "empty" }, messages: [message] }],
  } };
}

test("retry omits only the empty failure, preserving completed work and other boundary edits", () => {
  const event = boundary();
  event.entries.push({ type: "custom", customType: "evidence" });
  const retry = new EmptyResponseRetry().prepare(event);
  assert.deepEqual(retry.result, { continue: true, entries: [event.entries[0],
    { type: "context_edit", targetId: "empty", replacement: null }] });
  assert.equal(event.context.contextMessages.length, 2);
});

test("three retries with backoff, then report failure; new requests get a new budget", () => {
  const retries = new EmptyResponseRetry();
  assert.deepEqual([1, 2, 3].map(() => retries.prepare(boundary()).delayMs), [2000, 4000, 8000]);
  assert.equal(retries.prepare(boundary()), undefined);
  retries.reset();
  assert.equal(retries.prepare(boundary()).attempt, 1);
});

test("do not replay partial responses, tool calls, cancellation, or unrelated errors", () => {
  for (const overrides of [
    { content: [{ type: "text", text: "partial" }] },
    { content: [{ type: "toolCall", name: "write" }] },
    { stopReason: "aborted" }, { errorMessage: "401 unauthorized" },
    { errorMessage: "maximum context length exceeded" },
  ]) assert.equal(new EmptyResponseRetry().prepare(boundary(overrides)), undefined);
  const cancelled = boundary();
  cancelled.outcome = "aborted";
  assert.equal(new EmptyResponseRetry().prepare(cancelled), undefined);
});

test("unidentified source and successful settlement never trigger recovery", () => {
  const event = boundary();
  event.context.contextEntries = [];
  assert.equal(new EmptyResponseRetry().prepare(event), undefined);
  event.outcome = "completed";
  assert.equal(new EmptyResponseRetry().prepare(event), undefined);
});
