# CodeBuddy prompt and hook review

- [x] Regress system-only instructions and request-only ACP turns, including resume/recovery.
- [x] Disable inherited hooks through subprocess settings while preserving native auth/model settings.
- [x] Remove the incomplete prompt tool enumeration.
- [x] Verify installed CLI prompt placement and hook suppression with a positive hook control.
- [x] Run focused source checks and rebuild/verify the Windows package.
- [x] Prepare the verified changes for commit and push.

Keep permission ordering and native session behavior unchanged. No global CodeBuddy settings are edited.

## Evidence

- TDD: both new Node regressions failed before the fix (duplicated user instructions and missing hook override); all 12 Node cases passed after the initial implementation.
- Installed CodeBuddy 2.181.0 exposed a vendor compatibility issue: `disableAllHooks: true` alone did not suppress classic user hooks. That acceptance failed (`%TEMP%/gamesmith-verify-mz0oVY/results.json`). The final override also sets `hooks: null`; an empty object would merge inherited hook entries. This is a CLI-only overlay, not a configuration migration.
- Failed-only installed acceptance passed 2/2 entries in 29.4 seconds after that compatibility fix (`%TEMP%/gamesmith-verify-KSm7RV/results.json`). Both PreToolUse and PostToolUse sentinel commands ran in the positive control, then neither ran through production tools/resume/Stop/continuation. System/user placement checks passed. This is actual installed CLI transport against a deterministic localhost provider, not paid model inference.
- The automatic affected selector conservatively selects the full suite because this patch edits a verifier-only acceptance script. Final validation deliberately selects CodeBuddy's existing harness suite plus prompt contracts, verification contracts, package checks and installed acceptance; no shared controller/protocol behavior changed.
- Final focused run: 13 selected tests / 15 entries passed, 2,279 passing assertions, zero failures/skips/reused entries, in 247.9 seconds (`%TEMP%/gamesmith-verify-USySUS/results.json`). Includes package rebuild, all-harness prompt contracts, CodeBuddy lifecycle/recovery, assembly, verifier/pin contracts, package checks and installed CLI acceptance. This was not a full-suite run.
- Standalone rebuilt-PCK lifecycle run outside the checkout: 52/52 assertions passed (`%TEMP%/gamesmith-codebuddy-review-package-Adj8m4/results.json`). Tested package SHA-256: `0ecf19929b8615572a10958454a8c572247a89955d597bf8319b39a0d45957f4`.
- Final installed acceptance also proves native model selection remains intact and the isolated user settings file is byte-for-byte unchanged. No paid provider calls were made.
