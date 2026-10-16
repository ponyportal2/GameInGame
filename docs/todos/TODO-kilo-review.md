# Kilo review corrections

- [x] Reproduce stale native session and GET/HEAD routing with failing tests.
- [x] Add confirmed Kilo reset/archive UI and initialization retirement.
- [x] Use Kilo query routing; retain the tested /event endpoint.
- [x] Verify stale/reset/rename lifecycle and packaged runtime; attempt real model acceptance.
- [x] Rebuild Windows PCK and prepare the verified fix for commit/push.
- Finalization: commit/push on main, then verify the remote SHA; no GitHub CI.

## Implementation

Kilo alone implements reset/archive in its small controller; all three existing
UI gates now include Kilo. Busy/ownership checks and explicit confirmation remain
in place. Cancel preserves the reference, confirm archives it and retires runtime;
rename becomes possible until a fresh message saves new native history.

Only Kilo readiness failures retire the HTTP backend and mark the adapter for
host retirement. Saved-session lookup failure gives Settings reset instructions;
the old reference stays intact. OpenCode's reset and readiness policy is unchanged.
GET/HEAD use URL query directory routing only for Kilo; mutating headers and the
tested `/event` endpoint remain. Docs say tested with 7.8.8 and show pinned install.

## Verification (2026-10-14)

The strict GET/HEAD fixture failed against the old header routing and passed after
the change. Stale-ID host regression exposed a missing retained `last_error`;
fixed Kilo error retention and reran the complete targeted set successfully.
The initial routing-failure run left test processes waiting; terminated only its
owned test process tree before final verification.

- All 133 Node tests passed, exit 0. Stale-session transport check verifies the
  failed backend is dead, the reference is preserved and the error is actionable.
- Kilo lifecycle (28 checks), Kilo forced Stop (15 checks), OpenCode lifecycle,
  and harness/settings/switching runners passed together, exit 0. This was a
  targeted host run, not another complete default suite.
- Rebuilt Windows PCK passes isolated package-content verification. Packaged
  Kilo fixture passes all 28 lifecycle checks, including stale resume, cancelled
  reset, archive/removal, rename before a new turn and renewed rename protection.
- Logs: `%TEMP%/gamesmith-kilo-review-node.log`, `gamesmith-kilo-review-host.log`,
  `gamesmith-kilo-review-package.log`, `gamesmith-kilo-review-package-fixture.log`.

- Real Kilo CLI 7.8.8 with the selected `kilo/stealth/glyph-cluster` passed the
  first eight acceptance checks: editing, headless testing, streaming, exact
  model, saved session, next-message recall and backend reuse. Reopen acceptance
  did not pass: the model received the correct history-only request in the same
  native session but changed the marker from 37 to 38, ran tools and requested
  reload despite explicit instructions not to do so. The runner was waiting for
  that unsolicited approval; terminated only its verified owned process tree.
  Native database inspection confirmed the exact incoming prompt/session and
  the model's subsequent tool calls. This run is a failed/aborted live acceptance,
  not a passing reopen, 65-second approval or Stop/resume result.
  Log: `%TEMP%/gamesmith-kilo-review-live.log`; isolated data:
  `%TEMP%/gamesmith-tests-LlHLip`. No product workaround added for model behavior.

No native credentials/settings changed and no GitHub CI started.
