# OpenCode harness

- [x] Write failing protocol, workspace/tool-policy, and harness UI regressions.
- [x] Implement headless adapter, native MCP bridge, persistent per-game sessions, and cancellation.
- [x] Add harness selection and disable unsupported model/compaction controls while preserving settings.
- [x] Verify deterministic lifecycle and real installed OpenCode editing/testing/resume.
- [x] Document, rebuild and verify Windows package.
- [x] Commit and push.

Verification: 11 Node adapter tests and Windows bootstrap Go tests pass. Host suites pass through the harness/lifecycle group (rerun together after fixing test settings leakage). Native OpenCode 1.19.0 on the installed free model created and headlessly tested a game, resumed the same conversation, and retained pending reload approval beyond 65 seconds. Cancellation regressions verify both CLI and MCP descendants stop; failed reload diagnostics allow repair in the same request. Rebuilt Windows launcher/PCK pass package checks; exported chooser/settings test passes. Restart the running app to load the updated package.
