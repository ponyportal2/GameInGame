# Chat correction and persistence

- [x] Regress whole-turn correction after commentary/tool/host interleaving, including fresh-app replay.
- [x] Add explicit reconciliation modes; preserve legacy latest-stream records.
- [x] Coalesce adjacent deltas, flushing on boundaries, periodic/size limits, replay, navigation, and shutdown.
- [x] Skip blank JSONL lines; verify source and package; rebuild and push.

## Implementation

Native canonical corrections explicitly record `whole_turn`; retry cleanup uses
`latest_stream`. Old records without a mode retain their original latest-stream
semantics. Whole-turn correction replaces assistant message/delta/end events
after the latest user request once, retaining thinking/tool/host evidence and
previous requests. Canonical text goes at the first removed assistant position,
or just after the user if no assistant prose existed. This intentionally loses
some assistant/tool interleaving for corrected turns.

One pending delta is coalesced in the UI, with a 500 ms monotonic flush interval
and 16,384-character threshold. Role/stream boundaries, every non-delta event,
replay, game navigation, and tree exit flush first. The buffer retains the
original game identity. Rendering remains immediate; a hard crash can lose the
last unflushed fragment. Blank JSONL lines are skipped before parsing.

## Verification

- Red: `%TEMP%/gamesmith-verify-Xx76qh/results.json` reproduced duplicate
  commentary and per-delta writes. Stopped the initial run after it reached
  failures; its large-text rendering fixture was unnecessarily expensive.
- Intermediate: `%TEMP%/gamesmith-verify-fyDxo4/results.json` fixed correction
  and batching but failed the periodic test's SceneTree-timer assumption.
  The test now waits using the same monotonic clock as production, and exercises
  the size limit through persistence without repeatedly rendering giant text.
- Focused: `%TEMP%/gamesmith-verify-FRRhyb/results.json`, 2/2 steps passed.
- Final source/package: `%TEMP%/gamesmith-verify-1WFT2A/results.json`, 17/17
  steps and 677 assertions passed, zero failures/skips. Includes rebuild,
  Codex Node fixtures, chat/recovery/native-recovery/Codex lifecycle, shared host
  and UI consumers, runtime assembly, and package structure/contents checks.
- Direct rebuilt-PCK execution of the same chat runner: 30 checks passed,
  exit code 0. Evidence: `%TEMP%/gamesmith-chat-packaged-acceptance/packaged.log`.
  The intentionally truncated JSON regression still emits its expected parse
  diagnostic; empty lines/EOF no longer do.
- No live provider calls, GitHub CI, or manual rendered UI acceptance.
