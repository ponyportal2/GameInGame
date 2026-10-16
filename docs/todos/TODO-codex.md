# Codex harness

- [x] Add failing protocol, workspace-tool and host lifecycle regressions.
- [x] Implement persistent Codex app-server transport, native thread persistence, live events and Stop.
- [x] Expose bounded workspace tools and existing GameSmith test/reload/Git tools.
- [x] Add Codex to creation and switching; leave model/provider/reasoning/compaction to Codex.
- [x] Exercise installed Codex with gpt-6-luna and xhigh using a test-only launcher.
- [x] Run Windows and Linux regressions, rebuild/verify package, update documentation, commit and push.

Production must not specify a model or reasoning effort. Native file/shell approvals are denied; GameSmith tools enforce the workspace and reload policies. Session ownership and five-second Stop fallback apply to Codex too.

Evidence:

- TDD: protocol tests initially failed on missing adapter; UI/switching assertions failed with only three harness choices. A backend-death regression then failed because the adapter remained alive; retirement fixed it.
- Node suites: 57 passing on Windows and Linux, including native approval denial, workspace escapes, explicit thread resume, default-setting inheritance, streaming reconciliation, Stop/reuse and EOF cleanup.
- Windows host suites: all 20 default scripts executed successfully across the broad run and continuation. The existing production bridge graceful-shutdown assertion failed once as `stop_method=unconfirmed`, then its unchanged 57-check suite passed on rerun. No unrelated shutdown implementation change was made.
- Linux host: harness creation/switching, four-harness ownership, Codex/OpenCode lifecycle, stalled cancellation and process-tree cleanup passed. Codex separately verified stalled initialization, interrupt RPC, and interrupt settlement, killing both adapter and native backend.
- Installed Codex 0.162.1: live `gpt-6-luna` / `xhigh` confirmed by native thread response; editing, headless tests, streaming, same-backend history, reopen resume, approved reload and native Stop/follow-up passed. This provider run emitted no reasoning-summary deltas; reasoning notification handling is covered by fixtures.
- Logs remain outside the repo under `%TEMP%/gamesmith-codex-*`; test workspaces are isolated. Native acceptance threads remain in Codex's own history. No global configuration or auth files were changed.
- Pi fake-provider integration: 140 checks passed. The final Codex protocol suites also passed again on Windows and Linux after the tool-completion status adjustment.
- Windows PCK rebuilt after the final runtime change. Packaged-content checks and the self-contained Windows package verifier passed. Restart GameSmith to load the new package.
- Global Codex configuration hashes matched before and after the final live test. Production supplies no model or reasoning override; the Luna/xhigh launcher is test-only.
