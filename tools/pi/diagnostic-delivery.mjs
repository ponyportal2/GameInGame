// Receipts remain pending until the exact response is present in Pi's session.
// Dropping pending metadata only permits duplicate notices; it never suppresses evidence.
export class DiagnosticDelivery {
  constructor(limit = 16) {
    this.limit = limit;
    this.pending = [];
  }

  retain(result, session, identity, text) {
    const id = result?.delivery_id;
    delete result?.delivery_id;
    if (!id || !text) return;
    this.pending.push({ id, anchor: session.getLeafId(), ...identity, text });
    if (this.pending.length > this.limit) this.pending.shift();
  }

  async confirm(session, commit) {
    const branch = session.getBranch();
    for (const receipt of [...this.pending]) {
      const anchor = receipt.anchor === null ? -1 : branch.findIndex(entry => entry.id === receipt.anchor);
      if (receipt.anchor !== null && anchor < 0) continue;
      const accepted = branch.slice(anchor + 1).some(entry => {
        if (receipt.customType) {
          return entry.type === "custom_message" && entry.customType === receipt.customType && entry.content === receipt.text;
        }
        const message = entry.message;
        if (entry.type !== "message" || message?.role !== "toolResult" || message.toolCallId !== receipt.toolCallId) return false;
        const text = (message.content || []).filter(part => part.type === "text").map(part => part.text).join("\n");
        return text === receipt.text || text === "Error: " + receipt.text;
      });
      if (!accepted) continue;
      const result = await commit(receipt.id);
      if (result?.ok) this.pending = this.pending.filter(item => item !== receipt);
    }
  }
}
