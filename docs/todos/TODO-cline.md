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

Re-verification on Cline 3.0.73 (2026-10-29):

- The live host runs with an isolated `HOME`, so the adapter resolved
  `providers.json` inside the temp directory and every session aborted with
  `Authentication required: Call authenticate before starting a session` even
  though the profile was logged in. `liveEnvironment()` now passes
  `CLINE_DIR` for Cline, the same way it already passes `COPILOT_HOME`,
  `CRUSH_GLOBAL_*` and `PI_CODING_AGENT_DIR`; the isolated `CLINE_DATA_DIR`
  still keeps session storage per game.
- The CLI upgrades itself on startup with
  `npm update --global cline --tag latest --min-release-age 0`, which bypasses
  the 7-day release-age floor and moved this profile from 3.0.73 to 3.0.74 on
  2026-10-29. The adapter now sets `CLINE_NO_AUTO_UPDATE=1` for its child so a
  game session cannot rewrite the user's global install mid-run. Reinstalling
  3.0.73 required `--force`: the running hub daemon held the 3.0.74 binary and
  the plain install left it on disk while updating only the wrapper metadata.
- The live runner asserted a `cline-free/` model prefix, which no longer
  exists; the profile's current free tier id is `reflection/beam-free`. It now
  compares the applied model against the profile's saved model instead of a
  hardcoded prefix, so a future rename cannot fail the check.
- Live acceptance on installed 3.0.73 (`cline --version` reports the binary,
  not the npm wrapper): 19/19 assertions in 114.4 s, evidence
  `%TEMP%/gamesmith-verify-bztEpn/results.json`. Version still 3.0.73 after the
  run, i.e. the auto-update suppression held.

Re-verification on Cline 3.0.74 (2026-10-30):

- The auto-update suppression is back. It was briefly removed on the theory
  that the adapter targets the ACP surface rather than one release, but the
  startup updater runs `npm update --global cline --tag latest
  --min-release-age 0`: it bypasses the 7-day floor and can replace the tested
  build with an unvetted release while a game is running. The 3.0.74 bundle
  still honours the variable (`if(process.env.CLINE_NO_AUTO_UPDATE==="1")return;`
  guards the update check), so the child keeps `CLINE_NO_AUTO_UPDATE=1`.
  `liveVersion()` in `tools/testing/verification-live.mjs` resolves the exact
  executable the adapter launches and `verify.mjs` fails the live run when the
  version moved. The player updates Cline; starting a game never rewrites the
  global install.
- 3.0.74 is installed, so the documented pin matches what was verified.
- Live acceptance on installed 3.0.74: 2/2 in 135.3 s, evidence
  `%TEMP%/gamesmith-verify-xqKXAD/results.json`. The run includes the real
  edit, headless startup, streaming, conversation/backend reuse, reload
  approval and native Stop checks.
