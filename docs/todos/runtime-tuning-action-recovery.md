# Runtime tuning and detached-action recovery

Scope: reusable/reactive tuning-helper guidance, recoverable pending-action
rejections, and an exact `expected` schema. Keep startup-test policy unchanged.

- [x] Add regressions and observe the intended failures.
- [x] Return outstanding action identity and complete poll arguments on rejection.
- [x] Require both `expected.class` and `expected.script`; cover unscripted parents.
- [x] Tighten existing guidance for reusable, readiness-safe tuning helpers.
- [x] Run affected consumer checks and verify the rebuilt Windows package.
- [x] Review changes and prepare the tested package for commit/push; verify the
  remote revision after pushing (reported in the delivery response).

## Verification

- RED: `%TEMP%/gamesmith-verify-Xbn7DL/results.json` — all three selected
  regressions failed for the intended missing schema, prompt clauses, and
  pending-action recovery fields. Existing unscripted-parent behavior passed.
- GREEN: `%TEMP%/gamesmith-verify-olhdc7/results.json` — 4/4 entries passed
  (three selected tests plus setup), 85.6 seconds. Includes actual detached
  Godot execution, all sixteen assembled tool surfaces, and production prompt
  generation with Blender enabled/disabled.
- Final affected selection is exhaustive because the shared supervisor retains
  its conservative unknown-input fallback. Leave selection policy unchanged.
- Broad affected run: `%TEMP%/gamesmith-verify-JxSY6R/results.json` passed
  122/122 entries (120 selected tests plus setup/build), 5,636 assertions,
  1,404.6 seconds. No failed, blocked, reused or skipped entries. One optional
  native Command-code provider subtest was skipped; no real-provider calls or
  GitHub CI were requested/run.
- The subsequent direct PCK workflow exposed a pre-existing fixture packaging
  issue: raw `.gd` source is compiled during export, so copying that fixture
  returned empty text. Initial PCK result: 483 passes / 3 related failures at
  `%TEMP%/gamesmith-tuning-pck-PFlm7l/workflow.log`. Preserve the fixture unchanged
  as `.gd.txt` and explicitly include it in the export; no production behavior
  change is needed.
- Final fixture/package rerun: `%TEMP%/gamesmith-verify-IagREn/results.json`,
  5/5 entries, 497 assertions, no failures/skips/reuse, 90.1 seconds. Covers the
  source workflow, actual package contents and Windows package structure.
- Final direct rebuilt-PCK workflow: exit 0, 486/486 assertions at
  `%TEMP%/gamesmith-tuning-pck-N3Voa6/workflow.log`. Uses isolated user data and
  real detached Godot processes. The broad run predates the fixture-only export
  correction; the final focused/package runs cover that correction.
- `git diff --check` passed. Prompt/schema checks establish the generated
  contract; they do not prove a particular model will follow the guidance.
