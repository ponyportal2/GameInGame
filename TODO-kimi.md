# Kimi Code integration

- [x] Probe installed native ACP, tool restrictions and selected model.
- [x] Add failing protocol/transport/lifecycle regressions, then adapter.
- [x] Integrate harness selection, switching, settings, launcher and package checks.
- [x] Run deterministic suites and real selected-model continuity/tool/Stop acceptance.
- [x] Export Windows package, verify packaged runtime, document evidence and commit.

## Evidence (Windows, installed native Kimi Code 2.1.1)

- TDD: new Node protocol/worker suites initially failed with the missing adapter; implemented adapter passes. Latest full Node run: 111 passed, 0 failed.
- Launcher: Go tests pass, including Kimi-only PATH, standard install without PATH and explicit override. Windows launcher rebuilt.
- Native ACP probe: selected `openrouter/poolside/laguna-s-2.1:free` inherited without model/auth override. Private default-profile probe reports only the allowed MCP tool (`TOOL_POLICY_RESTRICTED`).
- Targeted Godot selection/switch/settings, ownership and Kimi lifecycle tests pass. Fixture covers native current context, MCP editing/headless tools, manual/auto reload, backend reuse, resume/reset, readiness failures and stuck initialization/turn/cancellation.
- First real acceptance data: `%TEMP%/gamesmith-tests-1b9AaZ`. Game written and headless startup accepted; HTTP 429 native retries prevented the initial completion marker. The overall runner correctly exited 1. Subsequent real turns passed history/process reuse, reopen, selected model verification, 65-second reload approval, accepted reload and Stop/history resume. This is partial live acceptance, not a clean passing run.
- Final export structural check and isolated packaged Kimi fixture pass (actual directory in `%TEMP%/gamesmith-kimi-final-package.log`); Windows package verification passes. No packaged real-model acceptance claimed.
- Second isolated live acceptance: `%TEMP%/gamesmith-tests-akayvh`, completed with every check passing on the inherited selected free model. Editing/headless/streaming, process/history reuse, reopening, exact native model, 65-second manual approval, accepted reload and Stop/resume all passed. The first partial run remains recorded above.

- Broad host suite: first 21 runners passed; existing Grok Build fixture stalled immediately after initial reload approval and was explicitly terminated. Grok passed its separate rerun. The remainder exposed inherited auto-approval from AGY in Kimi's manual-approval fixture; Kimi now explicitly initializes that preference. AGY → Kimi → shutdown then passed together with exit 0 (`%TEMP%/gamesmith-kimi-host-final.log`). All 25 runners passed across these runs; the initial run is not claimed as an uninterrupted success. No Grok adapter changes were made.
- Tests use isolated games; native session/history files created by the real acceptance remain in Kimi's normal native store. Global provider/model configuration was not edited.
