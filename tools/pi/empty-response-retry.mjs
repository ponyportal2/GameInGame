// Recover only a failed request that produced no assistant content. Tool work
// stays in the immutable session; omit just the failed message from its context.
export class EmptyResponseRetry {
  constructor(maxRetries = 3) {
    this.maxRetries = maxRetries;
    this.reset();
  }

  reset() { this.attempt = 0; }

  recordSuccess(message) {
    // Successful provider requests end a failure streak. Tool results alone
    // do not: they are host output, not evidence the provider recovered.
    if (message?.role === "assistant" &&
        !["error", "aborted"].includes(message.stopReason) &&
        message.content?.length > 0) this.reset();
  }

  prepare(event) {
    if (event.outcome !== "error" || this.attempt >= this.maxRetries) return;
    const messages = event.context.contextMessages;
    const message = messages.at(-1);
    if (message?.role !== "assistant" || message.stopReason !== "error" ||
        message.errorMessage !== "Provider returned an empty response" ||
        message.content?.length !== 0) return;
    const owner = event.context.contextEntries.findLast(entry => entry.messages.includes(message));
    if (!owner) return;
    this.attempt++;
    return {
      attempt: this.attempt,
      maxRetries: this.maxRetries,
      delayMs: 2000 * 2 ** (this.attempt - 1),
      result: {
        entries: [...event.entries, { type: "context_edit", targetId: owner.sourceEntry.id, replacement: null }],
        continue: true,
      },
    };
  }
}
