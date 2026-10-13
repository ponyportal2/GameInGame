# Cursor CLI integration

Review follow-up:
- [x] Confirm the original live test did not prove model inheritance; evaluate native startup flags in isolated configuration.
- [x] Choose the explicit ACP-default contract and correct UI/docs/test claims; retain native ownership without automatic model synchronization.
- [x] Verify the exact ACP Auto/default on new/resumed sessions, run affected suites and rebuild package.
- [x] Review, commit and push the follow-up.

- [x] Add failing protocol, native launcher and lifecycle regressions.
- [x] Implement persistent ACP sessions, structured tool permissions and private native tool policy.
- [x] Add Cursor creation/switching/settings/session recovery, packaging and Windows detection.
- [x] Verify deterministic Node, host and launcher suites.
- [x] Verify installed Cursor: editing/testing, streaming, history/reopen, delayed reload approval and Stop/resume.
- [x] Rebuild and verify Windows package, review diff, commit and push.

Use Cursor's existing login and ACP Auto default; do not claim editor/interactive model inheritance. Native provider/reasoning/compaction remain Cursor-owned. No model timeout. Stop retires the backend tree to clear Cursor's cancelled MCP queue. Preserve existing untracked screenshots.

Verification:
- Review follow-up (2026-10-13): exact `default[]` verified on new session, reopen and Stop/resume, alongside real tools/headless testing, same-backend history, 65-second reload approval and approved reload. Evidence: `%TEMP%/gamesmith-tests-BCZw0j`; uses the isolated native same-version CLI bundle with normal saved login. Wrong-Grok native identity is rejected before conversation creation.
- The standard installed Cursor bundle had missing dependencies; its `index.js` and `node.exe` hashes matched the isolated bundle exactly. Restored only absent dependency directories (`@jsquash`, `better-sqlite3`, `bindings`, `file-uri-to-path`, `node-gyp-build`, `piscina`), preserving existing files/settings/login. The normal resolver then verified native identity, authentication and resumable ACP capability. Earlier `gamesmith-tests-n3g2CY` failed on reopen due to the incomplete install and is not a passing acceptance run.
- TDD: initial Cursor protocol/transport and sixth-harness host tests failed before their implementation; launcher regression failed before detection was added.
- All 82 Node tests pass; Go launcher tests pass.
- All 22 default host runners pass across split runs. The broad run reached Cline then stalled after approval; its isolated rerun, Cursor lifecycle and shutdown all passed. Logs: `%TEMP%/gamesmith-tests-d1WFqA`, `gamesmith-tests-YqhXsJ`. Updated ownership switching including Cursor also passes (`gamesmith-tests-ufI7jS`). No single uninterrupted whole-suite claim.
- Live Windows Cursor `2026.10.01-e373342`, native Auto/default[]: real game write, headless test/start/inspect/stop, assistant/thinking streaming, same-backend history, reopen/same session, reload approval held 65 seconds, approved reload, Stop/backend retirement and history resume all pass. Evidence: `%TEMP%/gamesmith-tests-Qj26N8`. The test wrapper restores native APPDATA only in Cursor's child process, preserving isolated Godot data.
- Windows launcher/PCK rebuilt; structural all-harness contents and self-contained package checks pass. Immutable packaged live smoke passes, including editing/headless testing, reload approval, Stop and history resume (`%TEMP%/gamesmith-cursor-package-AxFH79`). Earlier packaged run was invalidated by rebuilding its mounted PCK; do not overwrite a package during testing.
- Additional native-read probe attempted the read and did not expose a random secret; the assistant reported denial, but ACP did not provide a matching explicit tool-denial event. Its strict assertion was inconclusive, not a successful independent native-read enforcement test. Deterministic policy configuration and permission spoof/replay/argument tests pass. Native tool policy is cooperative, not a code sandbox.
- No remote CI result is claimed; automatic workflows remain disabled. Screenshots stay untracked and excluded from exports.
