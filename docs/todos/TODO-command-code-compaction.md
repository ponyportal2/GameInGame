# Command-code compaction threshold

- [x] Add failing tests for context accounting, native compaction transport, and settings.
- [x] Run native /compact through ACP against the same per-game session.
- [x] Expose and persist the threshold and manual compaction; keep native policy controls disabled.
- [x] Verify cancellation, failure/no-op behavior, resume, and installed CLI integration.
- [x] Run relevant regression checks, rebuild Windows PCK.

Validation: Node protocol/ACP tests passed (7); host settings, threshold equality/zero, cached context, native failure/no-op, reopen, and process-tree cancellation passed. Command-code lifecycle repair/reload regression passed. Live command-code 1.79.2: native summary reduced synthetic context from 202,251 to 34,747 tokens, appended a checkpoint without rewriting original entries, and resumed the same session with COMPACTION_TEST_37 intact. Reliability regression: 92 passed, 0 failed. Windows PCK export and bundled-module checks passed.
