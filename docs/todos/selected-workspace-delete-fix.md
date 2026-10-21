# Selected workspace delete fix

- [x] Review ds changes; retain only recursive-delete diagnostics and regression.
- [x] Demonstrate the regression fails before the production fix.
- [x] Apply the fix and pass focused source/package verification.
- [x] Include only selected changes in one main commit; align ds with it.

Dormant read/search changes and the ds package are excluded. Preserve main's
before-state workflow instructions and rebuild its package from source.

## Verification

- Red: `host:test` failed the two new diagnostic assertions before the fix;
  the locked file was opened successfully and deletion succeeded after release.
  Evidence: `%TEMP%/gamesmith-verify-IXZLLL/results.json`.
- Source/package run: build, setup, `host:test` (184 assertions), and package
  structure passed. Package contents failed its detached injection/mouse action
  because the test game was no longer running. This was not an all-green run.
  Evidence: `%TEMP%/gamesmith-verify-qop6N8/results.json`.
- Unchanged-code `--rerun-failed` passed setup and package contents in 59.5s.
  Evidence: `%TEMP%/gamesmith-verify-0tc3Sb/results.json`.
- `git diff --check` passed. No full suite, provider calls, or CI dispatched.
