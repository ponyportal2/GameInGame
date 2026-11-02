# Adversarial review fixes

Follow-up to `codebuddy-adversarial-review.md`, reviewed baseline `b40ee66`.

- [x] Regress Pi destination overwrite through the production-assembled extension.
- [x] Regress scoped host Git diffs, including literal names and unsafe paths.
- [x] Regress nested `.git` refusal and actual Windows-hidden file deletion.
- [x] Apply the smallest fixes; retain unstaged Git semantics and link confinement.
- [x] Run focused regressions, affected consumer coverage, and rebuilt package checks.
- [x] Record outcomes and limitations for delivery with the source and rebuilt PCK.

Recursive deletion will refuse trees containing reserved repository metadata before
removing entries. This is an eligibility check, not rollback or a filesystem transaction.
The unverified percent-expansion launch concern is outside this patch.

## Development evidence

- Red run: `gamesmith-verify-WRsmSt`, both selected suites failed on the new
  move/delete/diff assertions. Tightening the hidden fixture exposed that `attrib`
  could return success without changing this fixture's attribute. The final red
  host run (`gamesmith-verify-ZAIgES`) sets and checks the attribute through
  FileAccess, then fails both hidden-deletion assertions: 92 passed / 17 failed.
- Green focused rerun: `gamesmith-verify-nAGP1T`, 3/3 entries passed in 7.7s
  (`node:workspace-paths`, `host:workspace_ops`, and import setup). A final
  consumer run will include the additional Git-file/hidden-metadata cases.
- The changes preserve unstaged diff behavior. Paths are literal (including
  bracket characters), workspace-relative, and reject traversal/linked targets.
  Destructive native path validation now reserves nested `.git` segments too.
- The affected selector chooses the complete deterministic inventory because
  GitService has no narrow dependency map and the shared tool/path modules reach
  every native harness. Use that selection once; do not change test-selection
  policy or add a new mapping as part of these fixes.

## Final verification

- `node tools/testing/verify.mjs --suite affected --since main --output summary`
  completed successfully: 106 selected / 108 entries, 4,329 passing assertions,
  zero failures, blocked, interrupted, reused, or skipped entries; 1,263.0s
  (21m03s). Results: `%TEMP%/gamesmith-verify-4L78tc/results.json`.
  This includes all assembled harness consumers, source regressions, package
  structure/content checks, and launcher unit tests. Inputs stayed unchanged
  during the run. No failed-only rerun was needed for this final run.
- Rebuilt PCK executed `res://tests/workspace_ops_runner.gd` directly in a
  separate isolated data directory: 111 passed / zero failed, exit 0, 1.4s.
  Evidence: `%TEMP%/gamesmith-packaged-workspace-SPxFgY/results.json` and
  `runner.log`. This separately verifies the actual packaged implementation.
- Tested PCK SHA-256:
  `9684a491068b292a399fd671a6c3d03565f27563d5a8b4a8c806dea64ddd9432`.
- Deterministic fixtures and real local filesystem/Git operations only; no
  real-provider calls or GitHub CI dispatch. Case-only Pi renames still require
  an intermediate name. Prechecks do not make filesystem operations atomic
  against concurrent external modification.
