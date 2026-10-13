# Cursor CLI integration

- [x] Add failing protocol, native launcher and lifecycle regressions.
- [x] Implement persistent ACP sessions, structured tool permissions and private native tool policy.
- [x] Add Cursor creation/switching/settings/session recovery, packaging and Windows detection.
- [x] Verify deterministic Node, host and launcher suites.
- [x] Verify installed Cursor: editing/testing, streaming, history/reopen, delayed reload approval and Stop/resume.
- [x] Rebuild and verify Windows package, review diff, commit and push.

Use Cursor's existing login and native model/provider/reasoning/compaction settings. No model timeout. Stop retires the backend tree to clear Cursor's cancelled MCP queue. Preserve existing untracked screenshots.

Verification:
- TDD: initial Cursor protocol/transport and sixth-harness host tests failed before their implementation; launcher regression failed before detection was added.
- All 82 Node tests pass; Go launcher tests pass.
- All 22 default host runners pass across split runs. The broad run reached Cline then stalled after approval; its isolated rerun, Cursor lifecycle and shutdown all passed. Logs: `%TEMP%/gamesmith-tests-d1WFqA`, `gamesmith-tests-YqhXsJ`. Updated ownership switching including Cursor also passes (`gamesmith-tests-ufI7jS`). No single uninterrupted whole-suite claim.
- Live Windows Cursor `2026.10.01-e373342`, native Auto/default[]: real game write, headless test/start/inspect/stop, assistant/thinking streaming, same-backend history, reopen/same session, reload approval held 65 seconds, approved reload, Stop/backend retirement and history resume all pass. Evidence: `%TEMP%/gamesmith-tests-Qj26N8`. The test wrapper restores native APPDATA only in Cursor's child process, preserving isolated Godot data.
- Windows launcher/PCK rebuilt; structural all-harness contents and self-contained package checks pass. Immutable packaged live smoke passes, including editing/headless testing, reload approval, Stop and history resume (`%TEMP%/gamesmith-cursor-package-AxFH79`). Earlier packaged run was invalidated by rebuilding its mounted PCK; do not overwrite a package during testing.
- Additional native-read probe attempted the read and did not expose a random secret; the assistant reported denial, but ACP did not provide a matching explicit tool-denial event. Its strict assertion was inconclusive, not a successful independent native-read enforcement test. Deterministic policy configuration and permission spoof/replay/argument tests pass. Native tool policy is cooperative, not a code sandbox.
- No remote CI result is claimed; automatic workflows remain disabled. Screenshots stay untracked and excluded from exports.
