# Runtime child review fixes

- [x] Regress approval, smoke survival, and serialized preload freshness.
- [x] Reuse approval UI with independent child auto-approval setting.
- [x] Check injected identity after smoke; refresh serialized preload caches.
- [x] Run source and packaged checks and rebuild the Windows package.
- [x] Prepare reviewed source changes, evidence, and the rebuilt package for commit.

## Implementation

Child additions use the existing pending approval lifecycle before preflight or
live execution. The UI says **Allow Child Code** and settings expose
**Automatically approve live child additions**, independently off by default.
The shared controller contract is exercised for all 14 harnesses, including stale
approvals and cancellation. Removal still only accepts GameSmith-injected nodes.

After the smoke window, the original child must still resolve, not be queued for
deletion, and retain its original parent and name. Workspace resource cache
detachment covers scripts, serialized resources/scenes, shaders, and cached
embedded resources. This walks already-loaded resource values, not a dependency
file graph. Existing objects retain their values; rejected loads restore cache
identities. Injection restores the old cache after compiling the fresh child.

## Verification (2026-10-20)

Artifacts are under `%TEMP%/`.

- RED: `gamesmith-verify-WVLkYW/results.json` reproduced approval, clean
  deletion/rename/reparent, and serialized preload defects before implementation.
- Initial focused run `gamesmith-verify-oVV5pb/results.json`: settings and prompt
  contracts passed; runtime children had two assertions fail when a preflight
  passed execution but did not confirm graceful cleanup. Exact unchanged rerun
  `gamesmith-verify-gsmWOa/results.json` passed (101 child assertions).
- Intermediate broader run `gamesmith-verify-P0InFl` was deliberately interrupted
  after an isolated probe exposed stale embedded subresources. Its incomplete
  result is not passing evidence. Added embedded-resource regressions and fixed
  the cache boundary before the final run.
- Final broad run `gamesmith-verify-oKvXdy/results.json`: **24 passed, 2 failed**,
  615.1 seconds. Includes a fresh package build, source tests, all-harness
  assembly/prompt contracts, settings/layout, cache/policy tests, child injection,
  reload preflight, detached test controls, bridge/shutdown, native lifecycle
  fixtures, and packaged contents/structure. Runtime children: **104 passed,
  zero failed**. The rebuilt package exercised real child Godot processes and
  required consent before live insertion.
- Exact unchanged `--rerun-failed` run
  `gamesmith-verify-OCC2oo/results.json`: **3 passed, zero failed**, 67.8 seconds
  (setup plus `host:runtime_properties` and `host:cline_lifecycle`). Initial
  failures were a persistent-edit reload rejection and Cline reload/session
  lifecycle assertions; neither required a code or timeout change to pass.
- Harness tests used deterministic native fixtures, not real provider calls.
  No GitHub CI dispatched. User game files, `Brain.txt`, and the unrelated
  archive were left untouched.
