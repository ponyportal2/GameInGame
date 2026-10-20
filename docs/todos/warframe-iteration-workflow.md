# Warframe iteration workflow

- [x] Regress native log cursor schemas and actual public log filtering.
- [x] Bound bridge action waiting without blocking or resubmitting; retain pending fallback.
- [x] Expose detached late injection and narrow mouse-button events; test original grenade behavior.
- [x] Tighten existing prompt evidence/workflow clauses.
- [x] Test native continuation boundary without adding host-owned history.
- [x] Focused source verification and rebuilt package acceptance, retaining failures and limitations.

Preserve unrelated local files. No production game reloads or workspace edits during review/replay.

## Scope and evidence

The shared native catalogs now advertise exclusive `cursor`/`next_cursor`, matching
the existing reader. Fast actions await at the asynchronous bridge for up to
300 ms; slower actions retain their original ID and pending/poll behavior.
Detached `inject_child` reuses structural validation and survival smoke; it never
promotes code into the live game or changes live approval. `mouse_button` sends
real button events, with narrowly validated coordinates and button indices.

TDD: initial catalog assertions failed for all 14 assembled harnesses. The first
focused green run passed all three selected entries, including 22 workflow
assertions (`gamesmith-verify-o263IV`). The broader source/package run
`gamesmith-verify-qF9WBh` passed 16 entries and failed four: a new test wrongly
assumed no pending fallback, a packaged test had a duplicate local variable,
and existing process/child suites reported cleanup failures. The first two test
issues were corrected. This was not one clean run.

Final focused evidence:

- `gamesmith-verify-HkV2Z6`: setup and workflow passed with stable inputs;
  26 workflow assertions, 21.1 seconds total.
- `gamesmith-verify-bUyWlD`: catalog registrations (15 tests), actual harness
  assembly (14 assertions), and package structure passed. Package contents failed
  its graceful-shutdown check. The unchanged failed-only rerun
  `gamesmith-verify-WlFzEU` passed setup and package contents in 56.0 seconds.
- Shared prompt contracts, reload preflight, OpenCode event/server/continuation,
  Command Code consumers, tool-output, verifier and chat-test-process suites
  passed in the broader run above. No full-suite green result is claimed.
- Existing `host:runtime_children` remains unresolved: the last attempt
  (`gamesmith-verify-zjyOUE`) failed two serialized-resource reload assertions,
  then raised a script exception in the following rejection check. Its stalled
  runner was terminated explicitly. An earlier unchanged rerun passed 104
  assertions, but its overall evidence was invalidated; that does not erase the
  latest failure. Detached-process coverage separately passed 95 assertions.

Several runs were invalidated rather than counted as reusable evidence:
`gamesmith-verify-fMqrpo` by my premature evidence-document edit;
`gamesmith-verify-zjyOUE` and `gamesmith-verify-vfqhfo` during concurrent checkout
edits/commits; `gamesmith-verify-dzvz9s` by an unrelated changing WorkBuddy memory
file included in the untracked-input fingerprint. Only that local metadata
directory was added to `.git/info/exclude`, leaving its contents untouched;
production/test inputs remain covered. The final focused runs above had stable
inputs. The packaged workflow fixture/PCK were committed concurrently in
`0170c03`; this patch preserves that fixture's pending-action recovery.

Actual Warframe copy replay (source): 11 assertions passed in 12,647 ms, one
headless process, 32 bridge calls including 23 automated pending polls. It entered
gameplay, late-injected the original grenade, delivered middle mouse, and observed
both a projectile and enemy damage. Startup and grenade hashes stayed unchanged.
The grenade fixture is byte-identical to that copy (SHA-256
`4232b09b895505a3af8776049f0313bbf1ba133be39704519405fb9938ff7fa2`).
Evidence: `%TEMP%/gamesmith-warframe-replay-ba98797e31b242649f2604c78e12bcf7/source2.log`.

The rebuilt PCK replay also passed 11 assertions in 12,725 ms, one headless
process, 34 bridge calls including 25 automated pending polls, and zero mechanic
or startup rewrites (`package2.log` in the same directory). Its first attempt
stalled at startup without publishing smoke counters; the unchanged retry passed.
The source replay initially exposed an overly strict one-shot test helper, which
was corrected to finish the same pending action rather than resubmit it.
Both successful replays observed the actual grenade projectile and enemy damage,
checked execution diagnostics, stopped cleanly and preserved source hashes.
No visual verification was performed. These automated poll counts are not model
turns and do not demonstrate a reduction in agent call count.

These are deterministic tool/CLI-fixture checks, not real provider calls or a
model-turn latency benchmark. The OpenCode fixture checks that the production
adapter carries a new request and continues across a simulated native compaction
event; it does not validate OpenCode's summarizer. Another WorkBuddy verifier was
running concurrently in the checkout, so these timings are not an isolated
performance comparison.
