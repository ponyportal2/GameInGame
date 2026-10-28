# Kilo CLI integration

- [x] Probe installed server, native model/default and session continuity.
- [x] Add failing tests and reuse OpenCode transport with explicit Kilo configuration.
- [x] Integrate create/switch/settings, ownership, launcher and packaging.
- [x] Verify deterministic and live tools, history, reload approval and Stop.
- [x] Rebuild package and record evidence.
- [x] Commit/push and verify remote.

Preserve native credentials/settings and untracked screenshots. Do not start GitHub CI.

## Implementation

Installed Kilo 7.8.8 exposes the OpenCode-compatible HTTP/SSE server API. Shared
`tools/opencode/` modules now accept the explicit `kilo` harness, selecting only
Kilo's executable override/npm entry, server banner, `KILO_*` environment,
authenticated loopback username and `x-kilo-directory` header. The small Kilo
controller inherits the OpenCode lifecycle and policy. No duplicate runtime
modules or native settings UI were added. Native histories and host references
are separate from OpenCode. Models, credentials, reasoning and compaction remain
Kilo-owned; the live installed selection is `kilo/stealth/glyph-cluster`.

The resolver and Kilo routing tests failed before implementation and passed
afterward. Transport fixtures enforce authentication/directory routing, exercise
persistent requests, native Stop, streaming/final reconciliation and EOF cleanup.
Host coverage includes switching, ownership, manual/automatic reload approval,
reload repair and five-second forced Stop at stuck start/abort/settle stages.

## Verification (2026-10-13)

- Node protocol/transport suites: 130 passed, 0 failed; `go test ./...` passed.
- One uninterrupted default host run completed all 29 runners with exit 0.
  Deliberately invalid generated games emit expected diagnostics during repair tests.
- Real installed Kilo 7.8.8 acceptance: 24 checks passed with exact inherited
  `kilo/stealth/glyph-cluster` selection on creation, reopen and Stop/resume.
  Verified real editing, headless testing, streaming, history/backend reuse,
  a 65-second player approval wait, actual reload and native Stop/resume.
- Rebuilt Windows launcher/PCK. Isolated packaged-content runner passed;
  packaged Kilo lifecycle fixture passed all 17 checks. Forced-Stop fixture
  passed all 15 checks for stalled start, abort and operation settlement.
- Logs: `%TEMP%/gamesmith-kilo-node.log`, `gamesmith-kilo-host-full.log`,
  `gamesmith-kilo-live.log`, `gamesmith-kilo-package.log` and
  `gamesmith-kilo-package-fixture.log`. Each final runner exited 0.

The first live attempt was partial: a real rename demonstrated that Kilo binds
native sessions to their original directory, leaving MCP unavailable after a
move. GameSmith now rejects rename once a Kilo reference exists, preserving both
workspace and native history, including when another harness is selected.
Pre-session rename and this protection are covered by fixtures and live checks.
The failed attempt remains in `%TEMP%/gamesmith-kilo-live-first-attempt.log`.
Kilo-only native permission defaults hide unsupported memory/delegation tools;
supported workspace tools and GameSmith MCP remain available. The first packaged
fixture attempt exposed a Windows slash-comparison bug in the fixture; corrected
the fixture and reran successfully. No global native settings or credentials were
changed, and no GitHub CI workflow was started.

## Kilo 7.8.15 stays; shared transport re-verified (2026-10-29)

Kilo is on the newest release at or above the 7-day floor: 7.8.15 is 8.8 days
old while 7.8.16 (5.8 d) through 7.8.23 (0.1 d) are inside it. Kilo keeps the
pre-v2 HTTP/SSE transport while OpenCode moved to ACP, so the shared
`tools/opencode` modules now branch on `config.harness === 'kilo'`.

Live acceptance re-ran on the shared code: 2/2 in 149.6 s
(`%TEMP%/gamesmith-verify-ahzG33/results.json`), covering the write/tool path,
the headless test bridge, native model reporting, history reuse, reopen,
rename rejection, reload approval and Stop/resume. The first attempt failed
only because the stealth model returned prose without calling any tool; the
identical rerun passed. Kilo unit and server suites pass.
