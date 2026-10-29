# OMP harness

- [x] Verify installed OMP 18.10.3 RPC, native settings and host-tool policy.
- [x] Add deterministic transport/policy/session tests before implementation.
- [x] Implement persistent RPC, bounded startup, explicit history/reset and Stop.
- [x] Add creation, switching, settings, launcher, package and documentation.
- [x] Run source/packaged lifecycle and real selected-model acceptance.
- [x] Rebuild Windows distribution and record evidence for publication.

Reuse GameSmith's existing bounded workspace tools, host bridge, editing lease,
Stop grace and native-session reset. OMP owns model/provider/reasoning/compaction.
Do not assume OMP's diverged extension API is interchangeable with Pi's extension.

## Verification, 2026-10-14

- Focused OMP Node tests: 13 passed. The complete Node suite: 183 tests,
  182 passed, zero failed, one optional Command-code provider test skipped.
  Log: `%TEMP%/gamesmith-omp-node-all.log`. The capture wrapper encountered a
  Windows console encoding error when printing the summary after Node exited 0;
  the captured test log contains the complete successful result.
- Source real OMP acceptance: 28/28, native exit 0, with the already-selected
  OpenRouter `dots-studio/dots-3-note-preview:free` model and native reasoning.
  Evidence: `%TEMP%/gamesmith-tests-Lf3NOu/engine-0.log`.
- Final rebuilt PCK: structural contents passed, fixture lifecycle 29/29,
  real acceptance 28/28, all native exits 0. Evidence:
  `%TEMP%/gamesmith-omp-package-_p6k36fw/`.
- Live checks cover edits, headless testing, streamed text/thinking, exact
  registered/active tools, inherited model, backend/history reuse, reopen,
  rename, a 65-second reload approval wait, actual reload and Stop/resume.
- TDD caught current-context accounting, lost earlier assistant rounds and
  premature completion after a yielded prompt. Regressions verify native
  `session_settled` handling, partial-stream reconciliation, forbidden tools,
  path escapes, nonce failure, missing-policy startup deadline, stale history,
  failed readiness and backend retirement.
- Editing ownership with OMP passed separately after extending its regression.
- The complete 32-runner host suite passed in one uninterrupted run, exit 0.
  Evidence: `%TEMP%/gamesmith-tests-oOrJF7/`. OMP lifecycle passed 29/29.
  The OMP-specific ownership extension was also run separately because it was
  added after the broad run had already completed that runner.
- Go launcher tests passed; Windows launcher and PCK were rebuilt. Verification
  is local Windows evidence; no GitHub Actions run was started. Linux and
  arbitrary future OMP versions have not been accepted. Native configured MCP
  processes may start; restrictions govern tool invocation, not process isolation.
  Tests verify native active tools and execution policy, not captured provider
  request schemas. Generated GDScript is not sandboxed.

## OMP 18.12.5 live re-verification (2026-10-29)

The installed CLI had moved from the 18.10.3 recorded above to 18.12.5, so the
live runner was re-run against it. The first attempt failed four assertions,
both of them in the runner rather than in the adapter:

- It compared the native model against `GAMESMITH_TEST_OMP_MODEL` even when
  that variable was unset, so an empty expectation could never match. It now
  treats the variable as optional, like the other live runners, and otherwise
  requires a non-empty reported model.
- It pinned the GameSmith host tool surface at 18 tools. The surface has since
  grown to 23 `gamesmith_*` tools, so the constant was stale. The check now
  asserts that no non-GameSmith tool reached the model and that the core set
  (read/write/edit/search/list, the test bridge, runtime inspection, property
  and reload tools, git commit) is present, which is the property that
  matters and does not rot with every new tool.

Re-run on 18.12.5: 2/2 in 182.1 s
(`%TEMP%/gamesmith-verify-0tyVbx/results.json`), 20 assertions, covering the
RPC turn, workspace writes, the headless test bridge, streaming, model
reporting, tool surface, thread reuse, reopen, rename/reopen and the reload
approval path. The failed first attempt is kept at
`%TEMP%/gamesmith-verify-2N0nVI/results.json`.
