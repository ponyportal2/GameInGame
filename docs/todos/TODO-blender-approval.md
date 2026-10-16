# Blender execution approval follow-up

- [x] Add a host-owned player approval UI for every explicit Blender Python run.
- [x] Show bounded UTF-8 script source (256 KiB maximum) and SHA-256; revalidate the original and execute a hash-checked private snapshot.
- [x] Keep reload auto-approval independent; reject tool-supplied approval, cancellation, changed arguments, stale operations and replay.
- [x] Wait at ACP permission time for Cline/Cursor/Grok, then pass a private one-use operation/arguments-bound receipt to MCP. Execution failures still return through the actual tool result.
- [x] Restrict Blender's environment and verify process birth, executable and unique job command line before orphan cleanup; block another job when cleanup cannot establish ownership.
- [x] Update shared instructions, README, packaging regression and deterministic/real Blender acceptance.
- [x] Leave Windows executable/PCK and the user's running app untouched. No package export/rebuild or GitHub CI requested/run.

Verification (source checkout, Windows, 2026-10-16):

- TDD: new approval/environment/ownership tests initially failed against the old implementation, then passed.
- Complete Node suite: 208 passed, 0 failed, 1 intentional skip. Final focused Blender tests: 17/17, including assembled MCP rejection without a grant.
- Cline/Cursor/Grok Node protocol/worker tests: 22/22. Separate 65-second approval waits passed for all three with a five-second fixture MCP execution deadline.
- Real installed Blender 5.2.2 LTS: 20/20; actual render, GLB export, saved blend reopen without Python approval, Godot GLB loading, headless game test, minimal environment, Stop, runtime retirement, and deliberately killed-supervisor cleanup.
- Shared host approval/UI regression: 79/79, including quick execution failure diagnostics and stale-operation grants.
- Focused existing bridge claim/reload/Cline/Cursor/Grok lifecycle runners: all five passed in one uninterrupted source run.
- Packaged runtime not rebuilt or retested, and no claim of a full 33-runner host pass or real-model acceptance for every harness in this change. Running packaged GameSmith retains its existing code.

Boundary: player consent and reduced environment do not sandbox Python. Approved code can access the user's filesystem, network and processes. Imports/resources are not frozen with the entry script. Process ownership recovery fails closed on unverifiable identity rather than killing an arbitrary saved PID.
