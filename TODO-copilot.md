# Copilot CLI integration

- [x] Inspect installed ACP handshake, history, native model and tool permissions.
- [x] Add failing protocol/lifecycle tests, then implement the Copilot adapter.
- [x] Add selector, switching, reset, launcher, package and documentation support.
- [x] Run deterministic suites and real selected-model acceptance.
- [x] Rebuild Windows package; no GitHub CI.
- [x] Finalize changes on main; push and compare the remote SHA before reporting completion.

Copilot owns model/provider/reasoning/compaction. GameSmith owns workspace tools,
reload approval, Stop fallback and explicit per-game session continuity.

## Implementation

Tested installed GitHub Copilot CLI 1.0.96, using its preview ACP stdio server.
Executable discovery is independent of Cursor/Grok's `agent`; Windows npm shims
resolve to the GitHub npm loader through Node. Native credentials and
`COPILOT_HOME` remain inherited. No model, reasoning or compaction overrides.

ACP ignores the tested startup `--agent` flag. GameSmith instead selects its
private profile through `session/set_config_option` and verifies the returned
agent before inference. Full instructions live in that profile; each prompt
contains only the player message. Exact startup/profile tool filters expose
GameSmith MCP tools only. All native ACP permission/filesystem/terminal requests
are denied. Global MCP processes can still start; this is invocation policy,
not process isolation. Shared MCP/workspace modules are assembled from the same
sources used by the controller and tested as that exact runtime bundle.

Ordinary turns reuse the backend and explicit native session. Stop retires the
process tree and resumes that session in a clean backend, with the existing
five-second host fallback. Missing history preserves its reference and directs
the user to confirmed Settings reset, which archives the old reference.

## Verification (2026-10-14)

- First ten server regressions failed before implementation (missing adapter).
- All 15 Copilot Node cases pass; all Node suites pass: 148/148, native exit 0.
  Evidence: `%TEMP%/gamesmith-copilot-node-all-ordered.log`.
- Windows launcher Go tests pass; rebuilt release EXE and PCK. Structural
  packaged-content runner passes: `%TEMP%/gamesmith-copilot-package.log`.
- Real source acceptance passes 24/24 with native Auto (`auto`), no override:
  `%TEMP%/gamesmith-copilot-live-3.log`. Covers editing, headless testing,
  streaming, same-backend history, reopen, rename, 65-second reload approval,
  actual reload, and Stop/resume.
- Isolated rebuilt PCK: fixture lifecycle passes 29/29 and real native acceptance
  passes 24/24, both native exit 0. Logs:
  `%TEMP%/gamesmith-copilot-package-fixture.log` and
  `%TEMP%/gamesmith-copilot-package-live.log`.
- Uninterrupted default host suite: all 30 runners pass, native exit 0, zero
  failed assertions. Evidence: `%TEMP%/gamesmith-copilot-host-all.log`, isolated
  application data `%TEMP%/gamesmith-tests-SkZ54J`.

Retained failures: the first real run lost native authentication because the
test isolated HOME; live tests now preserve native COPILOT_HOME without copying
credentials. The second run performed the requested operations but failed three
history assertions because a native startup information chunk omitted its line
ending; the adapter preserves the notice with a separator. The third run and
packaged live run pass. A full Node run exposed an existing fake-Codex logging
race: asynchronous log writes reordered its initialize handshake. The fixture
now logs synchronously; no Codex product behavior changed, and all 148 cases pass.

No visible thinking deltas occurred in the live Auto runs. Linux was not tested:
the installed WSL environment has no Node. No GitHub CI started. Preserve the
existing untracked screenshot files.
