# Copilot profile cleanup and harness documentation

- [x] Reproduce obsolete-profile accumulation and cover preservation on failed resume/selection.
- [x] Clean only obsolete generated UUID files after successful resume and exact profile selection.
- [x] Clarify Crush loopback access and Command-code loader persistence/conflict behavior.
- [x] Verify focused Node tests, lifecycle and real native resume; rebuild and check the Windows package.

Keep fresh per-runtime profile IDs. Leave unrelated agents and personal configuration untouched. Do not start GitHub CI.

Evidence:
- TDD: obsolete generated file remained after successful verified resume; regression failed before cleanup was added.
- Focused Node suite: 17 passed, 0 failed. Verifies old profile remains through resume/selection, failure preserves profiles/reference, successful selection removes obsolete UUID files, and unrelated names/directories/current profile survive.
- Source Copilot lifecycle: 29 passed, 0 failed (gamesmith-tests-IbhaYq/engine-0.log).
- Windows PCK rebuilt; structural verification passed. Package contents and isolated packaged Copilot lifecycle passed (29 checks); real packaged Copilot acceptance passed 36/36 (gs-copilot-cleanup-package-ovy84zpv/copilot_integration_runner.gd.log). Native model auto; same history survives reopen, rename and Stop with old-profile deletion verified after each selection. The 65-second approval wait and accepted reload pass.

Logs are under the Windows temporary directory. No remote CI was started; broader host/harness suites were not rerun for this focused change.
