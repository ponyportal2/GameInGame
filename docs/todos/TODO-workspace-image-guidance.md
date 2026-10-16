# Workspace image-loading instructions

- [x] Keep workspace asset guidance available with Blender disabled; include runtime PNG loading and child-node lookup.
- [x] State the single-image-job limit in shared prompts and both tool catalogs.
- [x] Cover Blender-on/off instructions and real PNG loading through the existing asset fixture.
- [x] Verify source/shared consumers and rebuild/check the Windows package.
- [x] Commit, push, and verify remote revision.

Scope: instructions and regressions only; no edits to the 2d game, loading policy, or image service.

Verification: `node tools/testing/verify.mjs --suite affected --build-package --output summary` passed 80/80 steps, zero failures/skips; evidence: `%TEMP%/gamesmith-verify-fB5bEY/results.json`. Includes actual PNG loading across reloads, renamed workspace, separate headless process, Blender-on/off prompt checks, all shared harness consumers and package checks. No live provider calls or GitHub CI.
