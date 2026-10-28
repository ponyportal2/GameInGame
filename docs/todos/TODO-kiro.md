# Kiro CLI integration

- [x] Pull merged Windows bridge ownership fix and rebuild the packaged host.
- [x] Probe installed ACP, native model selection, permissions and resume.
- [x] Add failing protocol/transport tests, implement adapter and deterministic fixture.
- [x] Integrate selection/switch/settings, ownership, launcher and packaging.
- [x] Run real native-model tools/history/reload/Stop acceptance.
- [x] Run suites, rebuild final Windows package and record evidence.
- [x] Commit/push and verify the remote revision.

No GitHub CI is started by this work. Preserve global CLI credentials/settings.

## Decisions and current evidence

- Pulled `a2d2a4e25351dd9e3de4e5a6eafc17309575db3a` and rebuilt its PCK before integration. Preserved untracked screenshots.
- Installed `%LOCALAPPDATA%/Kiro-Cli/kiro-cli.exe` reports `kiro-cli-chat 2.30.0`. Live ACP probe passed MCP echo and restart/history recall.
- Use explicitly selected V2 ACP. Private custom agent excludes native/global MCP tools; structured MCP identity, arguments and call ownership authorize permissions.
- Native configuration remains untouched. No saved `chat.defaultModel` is present; actual ACP model is `auto`. Tests use this native selection without a model override.
- TDD: new protocol suite initially failed missing adapter; transport suite failed all 7 cases before implementation. Actual native write exposed `kind=edit`; added failing regression and corrected the kind consistency check. All 12 Kiro Node cases now pass.
- First full live attempt failed actual edits/headless/reload because the initial kind check denied real writes. History/backend/reopen/rename worked. This attempt is not counted as passing acceptance. Evidence: `%TEMP%/gamesmith-kiro-live.log`, data `gamesmith-tests-LOExXG`.
- Targeted selection/switching, ownership and Kiro lifecycle runners passed, including reset, auto approval, initialization recovery and forced Stop at start/turn/cancel.
- All Node suites: 123 passed, 0 failed (`%TEMP%/gamesmith-kiro-node-all.log`). Windows launcher Go tests passed.
- Second live run passed uninterrupted, using native Auto with expected-model assertions at creation, reopen, rename/reopen and Stop/resume. Actual edits, headless testing, streamed assistant output, history/backend reuse and a 65-second reload approval passed. History-only recall checks provide no expected-value hint. Evidence: `%TEMP%/gamesmith-kiro-live-2.log`. Native Auto did not emit visible thinking deltas; no reasoning-stream claim is made.
- Rebuilt the Windows launcher and final PCK. Structural packaged-content regression passed (`%TEMP%/gamesmith-kiro-package.log`). The isolated packaged Kiro fixture lifecycle also passed, including permissions, reload, recovery, session reset and forced Stop at all three stages (`%TEMP%/gamesmith-kiro-package-fixture.log`, data `gamesmith-kiro-package-fixture-9WVjee`).
- Passing real live evidence uses data `gamesmith-tests-OoIlec`.
- The uninterrupted full host run completed all 27 runners with passing checks and no failed assertion (`%TEMP%/gamesmith-kiro-host-all.log`, data `gamesmith-tests-nFazmf`). The outer PowerShell command returned 1 because native stderr was redirected through `2>&1`: reproduced independently with `node -e "process.stderr.write('expected diagnostic\\n');"`, a successful Node process that also produced outer exit 1. The final shutdown runner additionally passed alone with recorded native exit 0 (`gamesmith-tests-dBPApj`). No product/test changes were made for this shell artifact. The original redirected run did not separately record Node's native exit code.

## V3 engine upgrade (2026-10-29)

- Installed `kiro-cli 2.35.1` reports itself current; its `acp` command defaults to `--agent-engine v2` and now also ships `v3`. The adapter targets **v3 only** — V2 is no longer supported.
- V3 differences verified by live probe: no `agentInfo` in `initialize` (identity comes from `agentCapabilities._meta.kiro.extensionMethods`); `--agent` is rejected, so the restricted profile is selected with `session/set_mode {modeId:'gamesmith'}`; the custom agent is only discovered when the workspace file is in V3's universal shape, which requires a `permissions` block — an empty `rules` array is enough and grants nothing; `session/new` returns `configOptions` for `mode`/`model`/`memoryReflection`/`autopilot`/`contentCollection`; native **autopilot defaults to on**, so it is set to `off` and verified from the `session/set_config_option` response before inference; session ids are `sess_<uuid>` and `session/load` needs no session-file hint; context usage arrives as `session_info_update` with `_meta.kiro.kind === 'context_usage'` instead of `_kiro.dev/metadata`.
- V3 announces a GameSmith call as `_meta.kiro.serverName` plus `rawInput.tool_id = 'gamesmith::<tool>'` and repeats the identity in `_meta.kiro.mcpTool.identity` on `session/request_permission`. `PermissionCalls` now binds the announcement, the namespaced tool id, the consent identity and the single-use call id.
- An earlier probe reported that v3 consent never executed a tool. That was a probe defect: the response was written as a JSON-RPC request (`method: 'session/request_permission'`) instead of a result. With a proper `result` the tool runs and returns its output.

- Live acceptance for V3 passed: `kiro_integration_runner.gd` returned `{"passed":2,"failed":0}` in 159.2s against installed `kiro-cli 2.35.1` with `--agent-engine v3`, native `auto` model and the restricted `gamesmith` mode (evidence `%TEMP%/gamesmith-verify-zdfMdH/results.json`).
- Node suites for the V3 rewrite: `tests/kiro.test.mjs` 3/3 and `tests/kiro-server.test.mjs` 12/12.
