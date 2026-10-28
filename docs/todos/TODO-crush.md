# Crush CLI integration

- [x] Inspect installed Crush 0.98.1 server API, native configuration, sessions and tool policy.
- [x] Add failing transport/protocol regressions, then implement the adapter.
- [x] Add harness selection/switching, recovery, launcher and packaging support.
- [x] Run deterministic host/Node suites and real selected-model acceptance.
- [x] Rebuild Windows package and verify isolated packaged behavior. Commit/push on main, verify remote, and do not start GitHub CI.

Crush owns model/provider/reasoning/compaction. GameSmith owns bounded tools,
headless testing, reload approval, Stop fallback and per-game native continuity.

## Decisions and verification

- Tested native version: Crush v0.98.1, tagged source `8b1824282eccc78cc62c188c245cf375230a18ce` (previously v0.96.1, `17a62b72549d60ac732a0a744382925467d5cfe7`). The 0.98.1 `internal/agent/tools` registry is byte-for-byte the same file set as 0.96.1, so the disabled-tool list is unchanged; only the pinned version moved. Use a persistent private HTTP server/workspace/database and explicit session IDs, not repeated one-shot runs or reconstructed chat.
- Crush omits its resolved agent tool registry from JSON. Pin the adapter to this verified version and validate the merged disabled-tools/MCP policy before inference. Unknown versions fail closed. Reuse the existing bounded Kiro MCP implementation and Cline lifecycle/support modules; Node tests assemble the exact eight runtime files selected by the controller.
- Native config arrays concatenate. Install the private policy only in the highest-priority native data directory; inherit native model, credentials, reasoning, compaction and cache without copying credential configuration. Reject a conflicting merged gamesmith MCP command, arguments or tool list.
- TDD: protocol imports initially failed before implementation. A delayed-MCP fixture reproduced updating the native agent before MCP discovery finished; the regression passes after readiness waits for MCP connection. A conflicting merged MCP-arguments fixture also failed before validation was added. Red evidence: `%TEMP%/gamesmith-crush-red-mcp.log` and `gamesmith-crush-red-merge.log`.
- All 163 Node tests pass, including 15 Crush tests. Windows launcher `go test ./...` passes. Final Node evidence: `%TEMP%/gamesmith-crush-full-node-final.log`.
- Source Crush lifecycle and harness-settings/switching runners pass. Source real acceptance passes 24/24 with native `dots-studio/dots-3-note-preview:free`, OpenRouter, high reasoning: editing, headless testing, text/reasoning streaming, backend/history reuse, reopen, rename, exact model, actual reload after a 65-second approval wait, and Stop/resume. Evidence: `%TEMP%/gamesmith-crush-live-final.log`.
- Retain unsuccessful live attempts: `gamesmith-crush-live-first.log` exposed the fixed MCP discovery race and a model refusing a redundant reload request. `gamesmith-crush-live.log` passed the core continuity tests, but the free model emitted its next intended tool invocation as XML inside reasoning and ended the turn without reload. This was confirmed in its native database. The final acceptance requests one explicit reload of the unchanged, already headless-tested game; there is no automatic replay or provider workaround in product code.
- Windows EXE/PCK rebuilt; isolated package-content regression passes. The complete packaged Crush fixture lifecycle passes, including manual/automatic reload, stale-session recovery and stuck startup/turn/cancel Stop fallback. Packaged real acceptance passes 24/24 using normal PATH discovery with the same free model/high reasoning, including 65-second approval, rename and Stop/resume. Evidence: `%TEMP%/gamesmith-crush-package-fixture.log` and `gamesmith-crush-package-live.log`. No native Crush server remains after the acceptance host closes.
- All 31 host runners pass in one uninterrupted complete run (native exit 0), including the bridge-claim regression, harness switching/ownership, every harness lifecycle, and shared shutdown/process-tree checks. Evidence: `%TEMP%/gamesmith-crush-full-host.log`. Node, launcher, source live and packaged live/fixture results above are local verification; no GitHub CI started.
- Rebuilt Windows PCK SHA256: `6300269d8e4a68a7157262ffd096721eaa83fe83fbd8539fc12d01ee218d3b18`. Launcher SHA256: `227c609046fd6ba0ad5f80f391a82eb8a554bac0b9ed15384831a0a368171a94`. Screenshot scratch files remain untracked.

## Crush 0.98.1 (2026-10-29)

The adapter now gates on `0.98.1` instead of `0.96.1`; 0.98.2 is only 5 days old
and stays inside the 7-day release floor. Installing the CLI surfaced a Windows
packaging detail: the npm package is a GoReleaser wrapper that puts a
`crush.cmd` shim on PATH and extracts the real binary to
`node_modules/@charmland/crush/bin/crush.exe`. `resolveExecutable` accepted
only `.exe` hits from `where.exe`, so a normal npm install produced "Crush CLI
was not found". It now maps a `.cmd` hit to the extracted binary and spawns
that directly, because Node refuses to run a `.cmd` without a shell and a
shell would re-parse the workspace path. A unit test covers both the missing
binary and the resolved path.

Live acceptance passes 2/2 in 125.2 s against the installed `crush v0.98.1`
(`%TEMP%/gamesmith-verify-gJ3F4a/results.json`), including the native MCP
tool path, the confined policy and the reload approval wait. Crush unit and
server suites pass 14/14.
