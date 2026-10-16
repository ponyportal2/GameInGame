# Codex review fixes

- [x] Add failing readiness, exact-turn and launcher regressions.
- [x] Retire failed initialization and preserve saved threads; provide a confirmed new-session action.
- [x] Bind dynamic tool execution to the exact accepted turn, including requests arriving before turn/start responds.
- [x] Include Codex in Windows launcher detection, warning and packaged instructions.
- [x] Run relevant Windows/Linux and live Luna/xhigh checks; rebuild launcher/PCK, document evidence, commit and push.

No automatic thread reset, generic request timeout, model/configuration override or speculative tool-schema migration.

Evidence:

- TDD reproduced a surviving initialization backend, pre-turn stale writes and a Codex-only launcher warning. Host regressions also caught loss of the actionable readiness error when the adapter exited before Windows pipes were read. Failed readiness now closes the native backend, reports a flagged error through a live pipe, and lets GameSmith retire the adapter before accepting another request.
- All 61 Node tests passed on Windows and Linux. Final Windows Codex-specific run: 13 passing. Early replayed/missing turn IDs cannot write, matching early calls work after turn acceptance, and Stop releases buffered calls while turn/start is stalled.
- Go launcher suite passed, including Codex alone on PATH, an explicit override and a JS entry point outside PATH. Launcher rebuilt with the release Windows GUI flags.
- Targeted Windows/Linux host runs passed: Codex lifecycle, harness creation/switching, ownership and UI layout. Final Codex lifecycle runs passed again after confirmation stacking/Escape assertions were added. Coverage includes immediate next-message recovery from initialize/config-read/resume failures, preservation of an unresumable thread, confirmed/cancelled new-session recovery, busy/ownership rejection, and three forced-Stop states with backend cleanup.
- The first Linux Node run checked PID disappearance before POSIX child reaping had completed. The assertion now waits up to one second for reaping; no production timeout was introduced.
- Installed Codex live acceptance: 17 assertions passed with native gpt-6-luna/xhigh confirmed, editing/headless tests, streaming, history/reopen, reload approval and native Stop/reuse. Global Codex config hashes matched before/after. Native reasoning summaries were not emitted in this run; fixture coverage remains the reasoning-stream evidence.
- Windows launcher and PCK rebuilt; packaged-content and self-contained package verification passed. Restart GameSmith to use the update. Logs are outside the repository at `%TEMP%/gamesmith-codex-review-*`; screenshots remain untracked. These are local results; automatic CI remains disabled.
- Tool definitions are unchanged. The installed CLI's generated thread/resume schema has no dynamicTools replacement field; document that existing threads retain their registry and revisit migration when definitions change.
