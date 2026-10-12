# Cline harness

- [x] Add failing ACP transport/configuration/session tests.
- [x] Implement persistent ACP backend, bounded GameSmith MCP tools, native settings inheritance and cancellation.
- [x] Add creation/switching/settings and Windows launcher/package support.
- [x] Verify deterministic suites and live selected free-model editing, headless testing, resume and reload.
- [x] Rebuild Windows package, document evidence, commit and push.

Implementation decisions:

- One persistent native ACP process per game controller; explicit native session load after reopen/switch. Native provider/model/reasoning/compaction stay with Cline.
- Private per-game native session storage and MCP registry; original provider credential store retains native refresh. API-key credentials go only into child environment, never GameSmith runtime files.
- ACP can silently fall back when its catalog omits a saved model. Apply the saved native choice with session/set_model before inference; regression covers request ordering.
- Bounded shared GameSmith workspace/Git/host tools through MCP; native shell/filesystem/delegation denied. Existing per-game editor ownership applies.
- Reload approval occurs in ACP before Cline's finite MCP deadline, then an operation-bound single-use grant permits host execution. Tested manual/automatic approval, stale grants and cancellation.
- No model deadlines. Native Stop preserves healthy backend; five-second host grace retires blocked process trees. Failed initialization retires runtime; failed resume preserves the pointer and offers confirmed session archival/reset.
- Do not persist session/new IDs until native prompt execution begins: a failed first-turn setup otherwise leaves an unresumable ID.
- ACP does not expose context usage; no estimated context count. Native test instructions explain running/accepted startup results to avoid repeated identical log polling triggering Cline's own guard.

Local verification (Windows, Cline 3.0.70):

- TDD failures confirmed for missing protocol implementation, native API-key inheritance, and catalog fallback selection; implemented regressions now pass.
- Node: all 70 tests pass. Go launcher: go test ./... passes, including Cline-only installation and explicit override detection.
- All 21 default host runners covered successfully across split runs. Initial full run stopped on existing test_process_runner.gd normal-stop assertion (56 pass, 1 fail); its final rerun passed all 57 checks. Remaining 13 runners passed separately. Final Cline lifecycle and ownership rerun also passed, including rejection of missing and previously consumed grants during an active turn, automatic approval, recovery/reset and forced Stop at initialization/prompt/cancellation.
- Windows EXE/PCK rebuilt; structural package check passes. Smoke from an isolated directory using only PCK resources passes Cline backend, real MCP editing, headless test and automatic reload.
- Earlier live runs exposed native authentication expiry, Windows MCP path quoting and silent ACP model fallback; do not count those as selected-free-model acceptance. Login refreshed by user; native metadata now confirms cline-free/mimo-v2.6-flash with saved xhigh reasoning selection.
- Selected-free-model live acceptance passed: actual main.gd marker=37, successful headless startup, assistant streaming, conversation/backend reuse, explicit native history after reopening, approval held for 65 seconds, approved live reload, native Stop and follow-up on the same backend. Independently checked native session metadata provider=cline/model=cline-free/mimo-v2.6-flash, and added that check to the live runner. No native thought deltas were observed with this model; that is not evidence of reasoning text streaming.
- Evidence logs: %TEMP%/gamesmith-cline-final-node.txt; gamesmith-cline-host-results.txt (initial failure); gamesmith-cline-remaining-host.txt; gamesmith-cline-acceptance-final.txt (live, lifecycle, 57/57 shutdown); gamesmith-cline-grant-final.txt (final active-turn grant and ownership checks). No remote CI claim.
- Automatic CI remains disabled. Existing untracked screenshots are preserved and excluded from package/staging.
