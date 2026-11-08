# Explicit voice recognition reinstall

- [x] Add the successful interpreter A → explicit reinstall with B regression.
- [x] Make explicit installation recreate only the private environment.
- [x] Run focused checks and rebuild/verify the package.
- [x] Prepare verified changes for commit and push.

Keep model downloads separate and unchanged. No interpreter registry or environment manager.

## Evidence

- TDD: the new successful A → reinstall B regression failed before the fix:
  environment creation ran only once. The other eleven Python cases passed.
- Final affected run: `node tools/testing/verify.mjs --suite affected --since main --output summary`.
  Four selected tests / six entries passed, 96 assertions, no failures, skips or
  reused results; 94.2 seconds. Includes all twelve Python worker cases (inside
  the Node voice contract), verifier contracts, 62 source voice UI assertions,
  package rebuild and nine packaged-content assertions.
  `%TEMP%/gamesmith-verify-aDUQnx/results.json`.
- The interpreter-switch and failure paths use controlled venv/pip fixtures;
  cached model bytes remain unchanged. No dependency/model downloads, physical
  microphone checks, real-provider calls or full-suite run were needed.
