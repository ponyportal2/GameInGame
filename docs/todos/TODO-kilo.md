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

## Kilo 7.8.18 accepted; shared transport re-verified (2026-10-30)

The TUI's self-upgrade to 7.8.18 is now the supported install rather than
something to revert. Kilo owns its own update policy and `kilo serve` - the
path GameSmith runs - does not check for updates, so a game session never
triggers one. The adapter targets the HTTP/SSE surface, not a single release.
Live acceptance on installed 7.8.18: 2/2 in 187.3 s,
`%TEMP%/gamesmith-verify-tCCW4O/results.json`, with the inherited
`kilo/stealth/glyph-cluster` model.

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

## Kilo's TUI upgrades itself past the floor (2026-10-29)

The installed 7.8.15 moved to 7.8.18 on its own at 2026-10-28T18:57Z. The CLI
logged `message=upgraded method=npm target=7.8.18` after an interactive
`kilo` run started in the home directory, and the npm cache shows the 7.8.18
tarball fetched at that moment. 7.8.18 is 3.3 days old, so that upgrade
bypassed the 7-day floor.

- `kilo serve`, the only path GameSmith uses, does not check for or install
  updates: two 75-second probes produced no update activity and no log entry,
  and the live acceptance below left the install on 7.8.15.
- `KILO_CONFIG_CONTENT` does not stop the TUI upgrade. Injecting
  `{"update":"disable"}` (the current schema key) and the deprecated
  `{"autoupdate":false}` both still ended on 7.8.18 after a 60-second TUI run,
  so the adapter has no lever here: a player who runs `kilo` interactively can
  move the install off the pinned version. Re-check `kilo --version` before
  treating live evidence as current.
- The global config file is the only documented switch; GameSmith deliberately
  does not write the player's Kilo configuration.

After restoring 7.8.15, live acceptance passed 2/2 in 158.0 s
(`%TEMP%/gamesmith-verify-cW8L9R/results.json`), covering the write/tool path,
the headless test bridge, native model reporting, history reuse, reopen,
rename rejection, reload approval and Stop/resume. `kilo --version` still
reported 7.8.15 after the run. `tests/kilo*.test.mjs`: 8/8.
