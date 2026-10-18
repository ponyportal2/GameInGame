# Late node lifecycle verification

- [x] Exercise initial and late child/subtree insertion in the bundled Godot engine.
- [x] Check processing, deferred initialization, cached children, and reinsertion.
- [x] Add shared agent guidance reflecting measured lifecycle behavior.
- [x] Verify source and package; prepare the focused commit and push.

## Findings

Godot 4.7.2 runs new child/subtree enter and ready callbacks synchronously when
added to an initialized parent. The parent's ready callback and cached child
list do not refresh. New nodes receive deferred, process and physics callbacks;
equal-priority parent physics runs before child physics, and explicit priority
can reverse that order. Reinsertion repeats enter, not ready, unless that node
requests ready. The request does not propagate to descendants. Disabled parents
still allow child initialization but prevent inherited processing until enabled.

These are engine-level fixtures and shared prompt instructions. No structural
runtime tool or reload acceptance behavior was added or changed.

## Verification

- Initial source fixture: 17 assertions passed, zero failures, bundled Godot
  4.7.2. Evidence: `%TEMP%/gamesmith-verify-WThJPQ/results.json`.
- `node tools/testing/verify.mjs --suite affected --output summary --build-package`:
  85 entries passed, zero failures, blocked, skips, interruptions or reused
  results; 1193.8 seconds. Evidence:
  `%TEMP%/gamesmith-verify-HGUlfn/results.json`.
- Rebuilt Windows PCK, independent isolated packaged runs: lifecycle 17/17;
  runtime properties and shared prompt/14-harness bridges 164/164. Evidence:
  `%TEMP%/gamesmith-late-lifecycle-package-m4IEAE/results.json`.
- No real-provider calls, live player-game edits, global configuration changes,
  or GitHub CI dispatch. Unrelated scratch archive preserved.
