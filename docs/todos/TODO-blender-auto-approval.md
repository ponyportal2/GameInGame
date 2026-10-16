# Blender automatic approval

- [x] Add an independent global setting, default off, available to every harness.
- [x] Apply it at the shared Blender execution boundary while retaining snapshots and private MCP grants.
- [x] Test persistence, independence, automatic execution and restoring manual approval.
- [x] Update instructions/docs. Leave the Windows executable and PCK untouched.

Source verification (Windows, 2026-10-16):

- TDD: settings regressions failed first for the missing default and control.
- Settings persistence/UI and shared Blender host runners pass; Blender host: 124 passed, 0 failed. Automatic execution checked for all 14 harnesses; Cline/Cursor/Grok receipts remain operation-bound and single-use.
- Focused Blender/Cline/Cursor/Grok Node suites: 39 passed, 0 failed.
- Real Blender acceptance: 20 passed, 0 failed; automatic render/export, then restored manual approval for subsequent executions, cancellation and orphan recovery.
- No Windows executable/PCK rebuild, running-app restart, package acceptance or GitHub CI run. Existing running application retains its previous code.
