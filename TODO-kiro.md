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
