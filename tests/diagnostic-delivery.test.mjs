import test from "node:test";
import assert from "node:assert/strict";
import { DiagnosticDelivery } from "../tools/pi/diagnostic-delivery.mjs";

function fixture(limit) {
  const branch = [{ id: "anchor", type: "message" }];
  const session = { getLeafId: () => branch.at(-1)?.id ?? null, getBranch: () => branch };
  const delivery = new DiagnosticDelivery(limit);
  const committed = [];
  const confirm = () => delivery.confirm(session, async id => { committed.push(id); return { ok: true }; });
  const tool = (text = "evidence", id = "call") => ({ id: "accepted", type: "message", message: {
    role: "toolResult", toolCallId: id, content: [{ type: "text", text }],
  } });
  return { branch, session, delivery, committed, confirm, tool };
}

test("reading a response does not acknowledge it; session insertion does", async () => {
  const f = fixture();
  const response = { delivery_id: "receipt", content: "evidence" };
  f.delivery.retain(response, f.session, { toolCallId: "call" }, response.content);
  assert.equal(response.delivery_id, undefined);
  await f.confirm();
  assert.deepEqual(f.committed, []);
  f.branch.push(f.tool());
  await f.confirm();
  await f.confirm();
  assert.deepEqual(f.committed, ["receipt"]);
});

test("old matching results and unpersisted tool events cannot confirm delivery", async () => {
  const f = fixture();
  f.branch.push(f.tool());
  f.delivery.retain({ delivery_id: "receipt" }, f.session, { toolCallId: "call" }, "evidence");
  await f.confirm();
  assert.deepEqual(f.committed, []);
});

for (const [name, text, id] of [["trimmed", "evide", "call"], ["changed", "replacement", "call"], ["unrelated call", "evidence", "other"]]) {
  test(`${name} results leave diagnostics unacknowledged`, async () => {
    const f = fixture();
    f.delivery.retain({ delivery_id: "receipt" }, f.session, { toolCallId: "call" }, "evidence");
    f.branch.push(f.tool(text, id));
    await f.confirm();
    assert.deepEqual(f.committed, []);
  });
}

test("failed tool results can confirm their complete diagnostic response", async () => {
  const f = fixture();
  f.delivery.retain({ delivery_id: "receipt" }, f.session, { toolCallId: "call" }, "evidence");
  const entry = f.tool("Error: evidence");
  entry.message.isError = true;
  f.branch.push(entry);
  await f.confirm();
  assert.deepEqual(f.committed, ["receipt"]);
});

test("hidden notices wait for their exact custom session entry", async () => {
  const f = fixture();
  f.delivery.retain({ delivery_id: "notice" }, f.session, { customType: "gamesmith-diagnostics" }, "2 errors");
  await f.confirm();
  assert.deepEqual(f.committed, []);
  f.branch.push({ id: "notice-entry", type: "custom_message", customType: "gamesmith-diagnostics", content: "2 errors", display: false });
  await f.confirm();
  assert.deepEqual(f.committed, ["notice"]);
});

test("switching away from the originating branch does not confirm a reused call", async () => {
  const f = fixture();
  f.delivery.retain({ delivery_id: "receipt" }, f.session, { toolCallId: "call" }, "evidence");
  f.branch.splice(0, f.branch.length, f.tool());
  await f.confirm();
  assert.deepEqual(f.committed, []);
});

test("bounded pending receipts discard conservatively and failed commits retry", async () => {
  const f = fixture(2);
  for (const id of ["one", "two", "three"]) {
    f.delivery.retain({ delivery_id: id }, f.session, { toolCallId: id }, "evidence");
    f.branch.push({ ...f.tool("evidence", id), id });
  }
  await f.delivery.confirm(f.session, async () => ({ ok: false }));
  assert.equal(f.delivery.pending.length, 2);
  await f.confirm();
  assert.deepEqual(f.committed, ["two", "three"]);
});
