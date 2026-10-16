# Preserve visible chat across reopening

- [x] Persist the same visible chat events across all harnesses, without adding UI history to native model context.
- [x] Preserve existing correction/retry behavior without erasing earlier commentary/tools.
- [x] Enable text selection and fix message boundaries/role labels during streaming.
- [x] Cover reopen/restart, legacy migration, interrupted streams, corrections, host/tool interleaving, selection, and literal BBCode.
- [x] Verify affected consumers, rebuild package, commit/push and verify remote revision.

## Implementation

Visible chat is recorded in per-game host metadata `chat.jsonl`, independent of the final-dialogue transcript used for native history import. It records exactly displayed message/delta/end events and replays them without adding duplicates or truncating the visible history to 200 entries. Existing dialogue is seeded atomically; older discarded intermediate messages are not reconstructed from native vendor databases. Retry/correction reconciliation removes the affected assistant stream while retaining earlier commentary/tools/host notices. Incomplete trailing records do not swallow subsequent messages. The file follows the existing per-game metadata rename/delete lifecycle.

Standalone chat messages close active streams before their own role header; resumed deltas receive a fresh header. System streams use HOST. RichTextLabel selection and its context menu are enabled; a regression selects all text and verifies the copyable text.

## Verification

- Initial focused development: `%TEMP%/gamesmith-verify-s5WrMR/results.json`, 4/4 steps passed (200 assertions).
- Final source/package run: `node tools/testing/verify.mjs --test host:chat_history,host:test,host:turn_recovery,host:ui_layout,host:reload_settings,host:library_actions,host:reliability,host:harness_assembly,node:verification,package:structure,package:contents --build-package --output errors`.
- Final evidence: `%TEMP%/gamesmith-verify-dUh0C7/results.json`, 13/13 steps passed, no failed/blocked/interrupted/skipped steps. Covers disk-backed fresh-app replay, all legacy messages (>200), partial streams, tool/host interleaving, retry recovery, native corrected-result signal, literal BBCode, selection, malformed trailing records and rebuilt-package contents/structure.
- No live provider calls or GitHub CI; no edits to the live `2d` workspace or its host metadata. Interaction assertions use isolated headless Godot UI, not a manual mouse-drag check in the running app.
