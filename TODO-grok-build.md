# Grok Build and Cursor separation

Review cleanup (2026-10-13): README's opening harness list includes Grok Build; the controller installs Grok's own MCP/approval sources rather than unused Grok copies alongside live Cline sources. All 10 Grok Node tests, the Grok host lifecycle runner (`%TEMP%/gamesmith-tests-WExMQu`), and rebuilt Windows package contents/self-contained checks pass. No additional live-provider run was needed for equivalent-module routing and documentation cleanup.

- [x] Probe installed Grok Build ACP identity, resumable sessions and structured MCP permissions.
- [x] Add failing regressions for wrong executable identity and Grok native permissions/session lifecycle.
- [x] Implement separate Grok Build choice, native adapter, persistent session and native-owned settings.
- [x] Make Cursor Auto warning explicit; keep executable resolution distinct from generic `agent`.
- [x] Verify deterministic Node/host/launcher tests and real Grok continuity/tools/Stop.
- [x] Rebuild and validate Windows package; record evidence and limitations.
- [x] Review, commit and push completed changes.

Evidence (Windows, 2026-10-13):
- PATH's first `agent.exe` belongs to Grok Build. Cursor resolves its bundled `node.exe/index.js` via `cursor-agent`; Grok resolves `grok.exe`. No generic `agent` fallback. Both ACP handshakes reject the other harness's native identity.
- TDD: Grok module/protocol tests, Cursor wrong-harness regression, seven-choice/switching host regression and Grok launcher detection failed before implementation. Actual Grok eager tool announcements exposed an additional failing regression before its permission tracker was corrected.
- All 93 Node tests and Go launcher tests pass. The final Grok fixture cleanup was followed by all 10 Grok Node tests passing.
- Harness switching/settings, Grok and Cursor lifecycle pass in `%TEMP%/gamesmith-tests-uHMazH`. Ownership switching and second-writer rejection across all seven harnesses, plus Cline lifecycle, pass in `gamesmith-tests-OuTlV8`. These are affected-suite runs, not a new uninterrupted run of all 23 host runners.
- Real Grok Build 1.0.52, native grok-4.7/high: GameSmith write, headless start/inspect/stop, streaming, same-backend/history, reopen/same native session, reload approval held 65 seconds, approved reload, Stop/backend retirement and history resume pass in `gamesmith-tests-hGRMmD`. The first live run (`gamesmith-tests-J1dX0F`) stalled after approval and was terminated; it is not a passing run. The successful rerun used the native-login wrapper's optional line-based ACP trace. No general model timeout was added.
- Windows launcher and PCK rebuilt (6,209,024 / 600,180 bytes); structural package contents and self-contained package checks pass. Packaged real-Grok replay was blocked before its first turn by native `Rate limited` (`gamesmith-grok-package-wW7sGi`); do not claim a packaged live acceptance pass.
- An immutable copy of the final PCK passes the complete Grok lifecycle suite with the native ACP fixture: tools/headless testing, permissions, approval/automatic reload, history/backend reuse, reset/recovery and forced Stop at initialization/turn/cancel. Evidence: `%TEMP%/gamesmith-grok-package-fixture-28NxH5`. Fixture executable is supplied outside the PCK; adapter/controller resources are loaded from the packaged artifact.
- Native Windows use verified; no live POSIX Grok result or remote CI result is claimed. Native tool restrictions remain cooperative policy, not an executable-code sandbox. Automatic workflows remain disabled; screenshots remain untracked and excluded from export.
