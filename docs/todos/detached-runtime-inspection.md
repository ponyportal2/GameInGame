# Detached runtime inspection and workflow corrections

- [x] Add failing regressions for scoped errors, detached pagination/search, provenance, and prompt contracts.
- [x] Reuse RuntimeProperties through the existing detached action bridge; preserve legacy inspect.
- [x] Extend inspect_runtime/runtime rg with optional run_id and document pending recovery.
- [x] Make surgical visual-target, live-capability, and rendered-validation prompt edits.
- [x] Run affected source/consumer coverage; rebuild and verify the Windows package.
- [x] Record results and prepare intended changes for delivery; report the pushed revision separately.

Scope: no camera metadata, detached revision tracking, new cursor protocol, or provider-bound vision acceptance in this patch.

## Verification

- RED: `%TEMP%\gamesmith-verify-ine7tC\results.json`: setup passed; four selected suites failed against the unimplemented contract. The workflow fixture also stopped at an unguarded empty-page assertion; its guard is now fixed.
- First implementation: `%TEMP%\gamesmith-verify-L0uzOm\results.json`: five entries passed, workflow failed because its expected Vector2 dictionary used integer values while JSON decoded floats. Checked the returned records and corrected the assertion to compare components; no production change was needed for that failure.
- Focused GREEN: `%TEMP%\gamesmith-verify-lQ5N7r\results.json`: five entries passed, zero failures. Includes actual detached-process pagination over 215 nodes, original instance identity checks, pending getter inspection without replay, expired/invalid/unknown/exited run rejection, legacy nested inspection, semantic prompt contracts across harnesses, real system-rg page filtering with bridge fixtures, cancellation and selector regressions.
- Earlier source coverage: runtime-properties and tool-registration suites passed in the first implementation run, including explicit rejection of detached handles carrying real live numeric IDs.
- An initial broad attempt was interrupted before host coverage after discovering Pi's separate reload description still required a redundant manual headless run. Corrected that description and added its actual-registration regression before restarting; the interrupted attempt is not passing evidence.
- Broad affected/shared-consumer run: `%TEMP%\gamesmith-verify-DqueIO\results.json`, 116 selected / 118 entries, 117 passed / 1 failed, 5,379 passing assertions, 23m57s. The only failure was `host:reload_settings` pinning the old phrase "successful headless test". After the run finished, updated that assertion to require headless-or-rendered testing of the current edits. No production change followed this run.
- Failed-only rerun: `%TEMP%\gamesmith-verify-jy4PnR\results.json`, 2/2 entries, 111 assertions, zero failures, 38.3s. The broad run is not described as initially green.
- Final package rebuild/verification: `%TEMP%\gamesmith-verify-vP554a\results.json`, 4/4 entries, 11 assertions, zero failures, 71.2s. Includes package contents execution and distribution structure.
- Direct rebuilt-PCK workflow: `%TEMP%\gamesmith-detached-pck-exit-EwQo7M\workflow.log`, 479/479 assertions and exit code 0, using isolated user data and actual detached child processes. An earlier PowerShell GUI launch completed its assertions but did not retain an exit code; repeated with Node process supervision to capture the exit explicitly.
- Source/fixture and packaged evidence above does not claim real-provider behavior or semantic vision acceptance. No GitHub CI dispatched.
