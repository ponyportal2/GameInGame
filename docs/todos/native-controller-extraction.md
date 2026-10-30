# Native controller extraction

Scope: reject unsupported OpenCode reset, then make Command-code and OpenCode
siblings beneath a small native lifecycle base. Preserve existing transports,
session identities, permission policy and provider-specific cancellation.

- [x] Add and demonstrate the cross-provider reset regression; fix OpenCode only.
- [x] Inventory inherited behavior and extract it without unrelated renaming.
- [x] Add focused behavioral contracts; retain real IPC lifecycle/recovery suites.
- [x] Audit Command-code consumers and regress affected selection.
- [x] Run focused checks, then one exhaustive deterministic run on final inputs.
- [x] Rebuild/verify packaged runtime; record selections, timing and limitations.

## Inheritance inventory

Before extraction, Command-code supplied OpenCode and all its descendants with:

| Member | Intended owner after extraction |
| --- | --- |
| `HarnessInventory`, `GamePromptScript`, `CommandSession` | Native base; shared assembly, prompt and GameSmith-side session protocol |
| `result_corrected`, `result_received`, `result_text`, `backend_pid` | Native base |
| `_send_player_attempt`, `_on_command_record` | Native base, preserving flags, ordering and generation checks |
| `settings_changed` | Native base; native settings remain harness-owned, no host runtime restart |
| `approve_reload`, `_fail` | Native base; retain native status and `last_error` |
| `_maybe_auto_compact` | No-op hook in native base; real implementation and attempt field remain Command-code-specific |
| `_start_command_runtime`, `_native_prompt`, `_harness_name` | Concrete controllers; base runtime construction fails explicitly |
| `compact_now`, `start_new_session` | Concrete controllers; OpenCode rejects both, descendants retain overrides |
| Base ownership/recovery/host bridge/cancellation | Still inherited from `AgentControllerBase`; OpenCode's own cancellation stays in place |

Existing pending working-tree changes are outside this refactor and are preserved.
No ACP migration, archive service or lifecycle framework is included.

## Affected coverage

Command-code controller changes (including its UID) now select 19 entries:
the three Command-code Node suites, lifecycle, compaction, its recovery scenario,
native reset/controller contracts, harness UI/switching, assembly, prompt contracts,
ownership, reload settings, runtime properties/children, Blender approvals, shared
turn recovery, verifier contracts and rebuilt package contents. The named
Command-code suite alone would omit several of those integration consumers.

`AgentControllerBase`, `NativeAgentController`, OpenCode/Cline inherited
controllers (and UIDs) retain exhaustive selection, currently 106 entries.
Unknown production/fixture inputs still use the exhaustive fallback. Selector
regressions assert exact concrete consumers and every native recovery/lifecycle
consumer at the shared boundary.

## Verification (2026-10-30)

- Reset regression failed before the explicit OpenCode rejection, then its
  unchanged-selection rerun passed (2/2 entries, 7.7 seconds).
  `%TEMP%/gamesmith-verify-Gxlfod/results.json` (red),
  `%TEMP%/gamesmith-verify-KUYlwK/results.json` (green).
- Initial focused native run: 8 entries passed, 1 failed, 180.6 seconds.
  Both new contracts, shared turn recovery, Command-code compaction/lifecycle,
  OpenCode lifecycle and Cline lifecycle passed. Codex's existing stalled-SETTLE
  Stop timing assertion failed; adapter/backend termination and resume passed.
  `%TEMP%/gamesmith-verify-n68iXL/results.json`.
- Exact unchanged-code failed-only Codex rerun passed (2/2 entries, 45.4 seconds).
  `%TEMP%/gamesmith-verify-MUqpS7/results.json`.
- Selector regression first failed because Command-code still selected the full
  inventory; after adding the audited mapping, both concrete and shared-boundary
  selector tests passed. No changes to product waits or Stop deadlines.
- Concrete Command-code affected run passed: 19 selected tests, 21 entries,
  343.6 seconds (3.2 build, 3.6 setup). No failed, reused or skipped entries;
  the opt-in installed-CLI assertion remains skipped inside its Node suite.
  `%TEMP%/gamesmith-verify-jTgcms/results.json`.
- Added two direct-base reflection assertions before the final exhaustive run
  to guard the actual sibling boundary as well as its behavior. These do not
  replace any real IPC lifecycle/recovery coverage.
- Final exhaustive run: `node tools/testing/verify.mjs --suite full --jobs 4
  --output summary` passed **108/108 entries**, 106 selected tests, in
  **1,220.1 seconds (20m20s)**. There were 4,276 passing assertions, zero failed
  assertions and one opt-in installed-CLI assertion skipped inside its Node
  suite. No failed, blocked, interrupted, reused or skipped entries. All native
  lifecycle/recovery suites, both new contracts (23 + 21 assertions), package
  structure/contents and launcher unit tests passed in this run.
  `%TEMP%/gamesmith-verify-H1Z9bf/results.json`.
- The exhaustive run rebuilt the PCK before import/testing. Its executable
  inputs remained frozen throughout. Immediately after both source and packaged
  runs, the complete verifier input hash still matched the exhaustive result:
  `bedfa01a1f8660cfeddf4bdfff1aacafef0916540dd4e128277816866e83b32c`.
  Only this evidence document was updated afterward. The base Git revision was
  `55e1e0f994427fe01a249e5cfe651b087acf844f`, with preserved pending changes;
  this is working-tree evidence, not evidence for a new committed revision.
- Direct packaged boundary checks: executed `native_controller_runner.gd` and
  `native_reset_runner.gd` from the rebuilt PCK with isolated user data and CWD.
  Both passed, 44/44 assertions, in 3.9 seconds combined. Exit status, assertion
  counts and fatal-script detection all agreed. PCK SHA-256 and individual logs
  are recorded in `%TEMP%/gamesmith-native-packaged-EYrDun/results.json`.

## Timing interpretation

The audited concrete Command-code selection took 343.6 seconds (5m44s), versus
1,220.1 seconds (20m20s) for this final exhaustive run: about 72% less wall time
for that narrower development selection. This compares different deliberate
coverage scopes, not a same-coverage execution-engine speedup. Shared native
changes still select all 106 tests, so this refactor itself required the full run.

For historical context, the preceding documented exhaustive checkpoint selected
103 tests/105 entries and took 1,358.3 seconds (`verification-speed.md`,
`%TEMP%/gamesmith-verify-ka4ss3/results.json`). The current run has additional
coverage and a different working tree; its lower elapsed time is not evidence
that moving method bodies accelerated individual tests. No parallel-safety
allowlist, product timeout or recovery wait was changed by this extraction.

The original eleven Command-code method bodies were compared against their
post-extraction owners; they remain unchanged, apart from the explanatory
comment on the native settings no-op. Runtime construction, session paths,
provider prompts, native transport policy and concrete compaction stay owned by
their existing controllers.

No real-provider calls, ACP transport migrations, commit, push or CI dispatch
are part of these checks. Existing pending changes remain separate in scope.

## Push preparation (2026-10-31)

On the user's push request, rebuilt the Windows PCK and reran package
structure/contents: **4/4 entries passed**, 58.8 seconds.
`%TEMP%/gamesmith-verify-Jb3gi6/results.json`.
The rebuilt PCK is byte-identical to the directly tested package above
(`f4e1e85686f2b85c12444a1792c6d297b9b749fcec4ba9e41a3b8a12646c21ba`).
Delivery includes the previously tested review follow-ups documented separately
in `review-followups.md`, which were already present in the exhaustive run.
