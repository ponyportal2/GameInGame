# Tool output bounds and focused discovery

- [x] Add failing regressions for discovery bounds, UTF-8 byte/line output ceilings, mutation/error semantics and assembled consumers.
- [x] Bound discovery and clarify inspect-first/live adjustment instructions.
- [x] Enforce 50 KiB / 2,000-line textual GameSmith outputs with usable recovery guidance.
- [x] Add bounded system-rg search after confirming source/runtime scope.
- [x] Run source/shared-consumer and rebuilt package acceptance; record limitations.
- [x] Review, commit, push and verify remote revision.

Preserve unrelated files. No changes to player workspaces or global native harness settings.

Evidence:
- TDD red: `gamesmith-verify-XtJohI` exposed missing output/search support and broad discovery amplification.
- Focused green: `gamesmith-verify-RzaLLY` passed 120 runtime assertions, 14 assembled tool-registration consumers plus the real 64-wall MCP response, and 12 output/search tests.
- Broad affected run: `gamesmith-verify-paBAD8` completed 80 passing checks and four stale fixture/count failures in 1,097.8 seconds. No host/package/launcher failures. Canonical production assembly includes the new module; older hand-copy fixtures did not.
- Corrected fixtures now use canonical runtime assembly. Failed-check rerun `gamesmith-verify-r83KhF`: all four selected checks plus setup passed (46.7 seconds).
- Final validation `gamesmith-verify-NlxZsN`: eight entries passed in 84.9 seconds, including package rebuild/setup, 14 output/search tests, 15 assembled runtime/MCP tests, 120 runtime assertions and both package acceptance checks. The opt-in real Command Code provider test was skipped (not configured), not live-provider evidence. Stable source ordering and every real Godot handle through MCP rg were verified.
- Publication includes the rebuilt Windows PCK; unrelated `tools/fake-openai-endpoint.zip` remains untracked. Commit/push uses `[skip ci]`; no CI dispatch.

Limits: deterministic fixtures and installed system rg; no real-provider timing replay or visual player-game verification. Native vendor tools retain their own output policies. Text truncation preserves summaries, not complete result records. Runtime search spans one bounded inspection page per call; live pages can shift. No external output store, resource hot reload, model-setting changes, or player workspace mutation.
