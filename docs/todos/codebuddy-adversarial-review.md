# CodeBuddy adversarial project review

Revision under review: `b40ee66fd4e9f5b2e1e79eee1d7303617bf42001` (`main`).
Reviewer: CodeBuddy CLI 2.179.2, explicitly selected `deepseek-v4.1-flash`, effort `max`. Maximum five debate rounds; stop early only on substantive agreement. Review-only: no production fixes or blanket safety claims.

- [x] Confirm clean baseline and installed CLI/model.
- [x] Gather independent review with concrete source evidence.
- [x] Verify findings, debate disagreements, and record each round.
- [x] Summarize agreed findings and limits; commit/push review record.

Rounds 2 onward must end their prompt with: "you can agree or disagree with everything, also be wary of speculative over-engineering"

## Agreed outcome

Stopped after three rounds (one incomplete exploration, two completed assessments). The host accepts R2 as P2, resolving the only severity question in round 3. Both sides therefore agree on the retained findings; no fourth or fifth call is needed. This is a source review plus targeted reproductions, not whole-project certification.

| ID | Priority | Agreed finding | Evidence | Smallest next step |
| --- | --- | --- | --- | --- |
| R1 | P2 | Pi move overwrites an existing destination. | Production-assembled Pi registration executed on Windows: destination sentinel replaced; success returned. | Refuse an existing destination before rename, matching the host tool. |
| R2 | P2 | Native host git_diff advertises path but discards it. | Schema at tools/opencode/host-tools.mjs:18; dispatcher at src/core/game_tools.gd:205; implementation at src/core/git_service.gd:39-40. | Honor a validated pathspec, preserving the current unstaged diff base, or remove the unsupported argument. |
| R3 | P3 | Recursive deletion removes nested reserved .git metadata. | Real WorkspaceOps in Godot and production-assembled Pi both removed vendor/.git/config. Direct host writes/deletes to that path are refused. | Enforce reserved-path policy for descendants; report refusal/preservation honestly. |
| R4 | P3 | Windows-hidden entries are skipped during host recursive deletion. | Real Hidden attribute: ordinary file removed, hidden file left, error advises closing files even though enumeration is the cause. | Set include_hidden before enumeration and regress the actual hidden-file case. |

OpenCode key-drift/acceptance-wiring claim withdrawn. Staged-only edits being absent from an explicitly unstaged diff are not scored. No automatic HEAD diff, filesystem transaction, rollback, readonly-retry framework, or additional permission architecture is justified by this review.

Unverified follow-up only: percent expansion in Pi's cmd.exe launch path for a percent-containing game name. Neither side reproduced it; it is not an accepted defect or a claim of safety.

No product fixes were requested or applied in this run. Review targets baseline b40ee66; the final documentation commit does not change that source revision. No full deterministic suite, packaged-runtime acceptance, or real OpenCode/provider workflow acceptance was run. CodeBuddy itself used a real DeepSeek provider through its CLI; the Pi reproductions used an assembled extension with a stubbed Type-schema dependency, not a Pi model invocation. Godot probes used the checked-in 4.7.2 executable against source, not the PCK. Temporary probe setup initially failed before execution (Windows file-URL/inline quoting); corrected file-based runners completed, and only their actual results are cited.

Raw transcripts/results remain under %TEMP%/gamesmith-codebuddy-review-b40ee66/. Targeted probe results remain under %TEMP%/gamesmith-review-probes-X7uGrR/. They are local ephemeral evidence; this document preserves the substantive reviews, rebuttal, reproduction outcomes, and limits. Review CLI durations: round 1 186.9s; round 2 310.9s; round 3 50.3s (548.1s total, excluding host verification).

## Round 1 — independent exploration; incomplete result

Requested a project-wide, risk-prioritized review, following shipped consumers and requiring actionable triggers rather than speculative redesign. Reviewer may read/search the checkout but cannot modify files or run commands.

CodeBuddy spent 186.9 seconds and hit `Max turns (40) exceeded`; CLI exit was zero but the structured result was `is_error: true`. It produced no final findings, so this round is not evidence of agreement or a clean audit. Reported model usage confirms `deepseek-v4.1-flash`. Raw evidence: `%TEMP%/gamesmith-codebuddy-review-b40ee66/round-1.jsonl` and `round-1.result.json`.

Host response: the unbounded exploration did not satisfy the request for an actionable review. Resume the existing context in round 2, disallow further tools, and require a final source-grounded assessment. This counts toward the five-round maximum.

## Round 2 — independent findings

Completed in 310.9 seconds. CLI exit 0; structured result successful; model `deepseek-v4.1-flash`. No reviewer-side test execution.

## Round 2 assessment — GameSmith @ b40ee66

Read-only review. No commands run, no tests executed, no packaged artifacts or logs inspected. This is a sample of the highest-risk paths, not an audit.

### What I actually verified in source

I traced the shipped paths for: harness catalog/assembly (`tools/agent/harnesses.json`, `src/agent/harness_inventory.gd`), the bridge dispatcher and approval state machine (`src/agent/agent_controller_base.gd`, `native_agent_controller.gd`, `opencode_agent_controller.gd`), both file-tool boundaries (`tools/pi/workspace-paths.mjs`, `src/core/workspace_ops.gd`, `tools/codex/tools.mjs`), OpenCode confinement (`tools/opencode/{protocol,worker,server,workspace-plugin,mcp}.mjs`), the Pi extension (`tools/pi/gamesmith-extension.ts`), and the reload/preflight/supervisor chain (`game_runner.gd`, `reload_preflight.gd`, `test_game_supervisor.gd`, `test_game_process.gd`). The OpenCode confinement is the best-defended area I read: default-deny permission list, post-resume mode pinning, a fresh guard token checked against the real workspace, and an acceptance script that drives the real CLI.

**No P1 is confirmed.** I found no broken promise in the sampled cooperative-confinement paths, and I am not treating the absence of an OS sandbox against generated GDScript as a defect — that is the documented v1 tradeoff (`docs/SPEC.md §16.1`, `docs/IMPLEMENTATION_NOTES.md:14`).

### Findings

**1. P2 — Pi `move_path` silently replaces an existing destination (data loss).**
`tools/pi/gamesmith-extension.ts:223-228` validates both paths, creates the parent, then calls `rename(from, to)` with no existence check. `fs.rename` replaces an existing file on Windows (`MoveFileEx` with replace-existing) and on POSIX. The host-side tool explicitly refuses this exact hazard: `src/core/workspace_ops.gd:121-124` ("Windows fails a rename onto an existing path while POSIX silently replaces it, so refuse…").
Trigger: default harness is Pi (`src/core/workspace_store.gd:30`); agent calls `move_path({from:"enemy.gd", to:"main.gd"})` while `main.gd` exists. Impact: `main.gd` is destroyed, the tool returns "Moved …", and the next reload loads the wrong file. Recovery only via Git. Smallest fix: `lstat(to)` and throw "Destination already exists" (mirror the GDScript message), or add a `mustNotExist` option to `workspacePath`.
*Verified:* both code paths. *Inference:* standard Node rename semantics (high confidence). Not reproduced.

**2. P3 — `git_diff` drops the `path` argument and hides staged changes.**
The MCP schema advertises `path` (`tools/opencode/host-tools.mjs:18`), the dispatcher passes args (`src/agent/agent_controller_base.gd:286-287`), but `src/core/game_tools.gd:58` calls `git_diff()` with no arguments and `src/core/git_service.gd:39-40` runs `git diff -- .`. Separately, `git_commit` runs `add -A` before committing (`git_service.gd:45-52`), so after a failed commit every change is staged and `git diff` returns empty.
Trigger: `git_diff({path:"main.gd"})` in a multi-file edit, or any diff after a failed `git_commit`. Impact: the model's verification evidence is wrong or truncated by the 50 KB transport bound (`host-tools.mjs:38-55`); it can conclude "no changes" or miss the file it asked about. Smallest fix: `git diff HEAD -- <validated path or .>`, and remove `path` from the schema if it will not be honored.
*Verified source behavior.*

**3. P3 — `delete_path` can remove nested `.git` metadata and can partially delete a tree.**
`src/core/workspace_ops.gd:129-144` checks `_reserved` only on the target path (`172-177`), while `_remove_tree_abs` (`198-218`) descends into every child without skipping `.git` and without `dir.include_hidden = true`. The metadata store's equivalent does both, plus a read-only fallback (`src/core/metadata_store.gd:120-150`). The Pi extension's `delete_path` (`gamesmith-extension.ts:205-208`) has the same nested-`.git` behavior via `rm -r`.
Trigger: `delete_path("vendor")` where `vendor/.git` exists, or a directory containing a Windows-hidden file. Impact: violates the stated ".git is reserved" promise and can leave a half-deleted directory with an error that does not say what was removed. The trigger is narrow because the shipped tool surface cannot create a nested `.git`; this is player/outside-tool territory. Smallest fix: skip or refuse `.git` entries inside `_remove_tree_abs`, set `include_hidden = true`, and add the read-only retry.
*Verified source; narrow reachability.*

**4. P3 — OpenCode native-enforcement evidence gap and a fail-open path default.**
`harnesses.json:168-172` lists only `opencode-events`, `opencode-server`, and `opencode` node suites. The only script that drives the real OpenCode CLI and proves junction/metadata enforcement is `tools/testing/verify-opencode-permissions.mjs`, which is not in that list; `tests/opencode.test.mjs:22-25` fabricates the hook event as `{tool,input:{path}}`, and `tools/testing/fake-opencode.mjs:17-18` explicitly says actual enforcement is covered elsewhere. Separately, `tools/opencode/workspace-plugin.js:15` uses `event.input.path ?? '.'`; if a native tool uses another key — `tools/opencode/gamesmith.mjs:15` itself checks `filePath`/`path`/`from`/`to`, evidence that keys vary — the hook validates the workspace root and allows the target, relying on native permissions that the plugin's own comment (`:5-6`) says do not resolve Windows junctions.
Impact: if the acceptance script is not wired into release verification, a regression in the only junction-resolving layer ships green; if the key changes, the hook silently no-ops for that tool. Fix: add the acceptance script to the release/live suite, and reject tools whose required path key is absent instead of defaulting to `'.'`.
*Evidence gap, not a demonstrated escape.* Caveat: I did not read `tools/testing/verify.mjs`, which may already run the script.

### Rejected as findings

- Generated GDScript calling `OS.execute`, reading credentials, or freezing the host: acknowledged same-process v1 risk, not a broken host-tool promise.
- The cooperative workspace policy being bypassable by generated code: not an OS sandbox by design; I did not score it.
- `pi_rpc_session.gd:256-260` builds a `cmd.exe /C "cd /D ... && pi ..."` line and game names may contain `%` (`path_utils.gd:7`), so a name like `%TEMP%` would expand and put Pi's cwd elsewhere. Real quoting bug, but the trigger is a player-chosen pathological name and the impact is the same cooperative-policy class; not scored.
- Packaged-build `--path` heuristic (`test_game_supervisor.gd:69-83`): if `globalize_path("res://")` is non-empty in a shipped build, every preflight would fail. The source comment asserts it is empty and packaged verification exists, so this is a reproduction question, not a finding.

### Coverage limits

I read roughly forty files in full and grepped a few more. I did **not** read: the body of `src/ui/app.gd` (only grep hits around open/reload/rename/delete), `runtime_log.gd`, `runtime_log_reader.gd`, `transcript_store.gd`, `json_store.gd`, `script_load_policy.gd`, `runtime_properties.gd`, `runtime_children.gd`, `test_game_watchdog.gd`, `test_evidence.gd`, most per-harness `server.mjs`/`worker.mjs` (Cline, Cursor, Kimi, Kiro, Copilot, Crush, OMP, Grok, AGY, Command-code), `verify.mjs`, `verification-plan.mjs`, `export_presets.cfg`, or any packaged binary/log. Findings 1–3 are source-confirmed code paths; their triggers were not reproduced. Finding 4 is an evidence gap. Absence of findings in unread areas is not evidence of correctness, and this small sample should not be read as an audit of the whole project.

**Bottom line:** the strongest parts are the OpenCode confinement and the reload/preflight cache-restore discipline; the weakest are the Pi extension's file-operation semantics (silent overwrite) and the diff surface the model uses to verify its own edits. The GDScript/Node duplication means the same semantic fix must be applied twice, and only the assembled-runtime suites prove the shipped behavior.

## Host verification before round 3

Host verification and rebuttal (round 3 input):
1. Accept P2 Pi move overwrite. I invoked the actual production-assembled Pi extension with only its Type dependency stubbed (same strategy as repository tests). In an isolated temporary game enemy.gd='source', main.gd='destination sentinel'. Executing registered move_path({from:'enemy.gd',to:'main.gd'}) returned 'Moved enemy.gd -> main.gd'; source disappeared and main.gd became 'source'. This is reproduced on Windows/Node 24.16.0. Keep the minimal destination-exists refusal; do not propose an atomic filesystem transaction framework.
2. Accept advertised git_diff.path being ignored, probably P2 rather than P3 because this is a shipped callable-schema correctness bug; open to keeping P3 if you justify impact. The schema advertises path at tools/opencode/host-tools.mjs:18 but game_tools.gd:205 calls git_diff() and git_service.gd:39-40 diffs all unstaged paths. I reproduced staged M status with empty 'git diff -- .' and nonempty 'git diff HEAD -- .'. However Pi explicitly describes its tool as showing UNSTAGED changes (gamesmith-extension.ts:242), so staged omission there is documented behavior, not itself a Pi bug. Keep path loss as the firm finding; treating all tools as HEAD diffs is a product decision. Host description only says workspace changes. git_diff HEAD also has an unborn-HEAD edge case; do not prescribe it unconditionally.
3. Accept nested .git deletion, P3, but split it from partial deletion. I ran the real WorkspaceOps.delete_path('vendor') through Godot 4.7.2 in an isolated directory with vendor/.git/config plus ordinary.txt: returned ok:true and both disappeared. Production-assembled Pi delete_path also deleted vendor/.git. Direct host mutations of nested .git paths are refused (workspace_ops.gd:172-177), whereas recursive deletion does not apply that rule to descendants. A whole-tree delete is not generally transactional; reporting failure after prior deletions is normal. Separately I used an actual Windows Hidden attribute: include_hidden defaults false; delete_path('vendor') removed ordinary.txt, left hidden.txt, and returned 'Delete failed (1). A file inside may still be open; stop the game and retry.' Closing files cannot fix that. This is a reproduced P3 hidden-enumeration/recovery bug, not a promise to roll back partial deletion. Minimal include_hidden=true justified; no blanket readonly/rollback machinery required by this evidence. MetadataStore is a deletion helper, not proof of a nested-.git protection rule.
4. Reject OpenCode issue as a current finding. verify-opencode-permissions.mjs drives the real supported OpenCode 2.1.2 and verifies read/write/edit/glob/grep use path, including junction escape, root/nested .git, guard-load fail-closed and resumed mode. verification-plan.mjs:112 resolves acceptance:opencode-permissions; tools/testing/README.md explicitly documents it as opt-in installed-CLI acceptance separate from fixture full suite. Its omission from the deterministic harness list is intentional. No evidence that supported 2.1.2 uses another key; old compatibility gamesmith.mjs is not such evidence. glob/grep may legitimately omit path and mean cwd. An upstream schema change would require rerunning existing acceptance; future key drift alone is speculative. Can note coverage limit, but do not require installed external binaries for deterministic release unless a concrete contract demands it.
5. Your unscored cmd.exe percent-name concern is plausible but neither of us has reproduced it. Keep as an unverified follow-up at most; don't accept a boundary escape as harmless simply because it begins from a user-supplied name. Do not add new findings outside source evidence.
No production files have been changed. Probe artifacts: %TEMP%/gamesmith-review-probes-X7uGrR/results.json and hidden-result.json. No full suite or real OpenCode/provider acceptance was run by host during this review.
Please debate these conclusions: retain only supported actionable findings, correct overstated claims, explicitly state any remaining disagreement and whether you substantively agree. You may disagree with severities or scopes, but do not manufacture objections or request speculative new architecture. No tools this round; the above is explicit source/probe evidence, and uninspected code must remain a limit.

## Round 3 — reviewer response to verified rebuttal

Completed in 50.3 seconds. Fresh compact context containing the complete round-2 review and host rebuttal; no source tools. CLI exit 0; structured result successful; model deepseek-v4.1-flash.

## Round 3 — response to host verification

**Substantive position:** I agree with the host on points 1, 3, 4, and 5, and agree with the substance of point 2 while keeping P2. One round-2 finding is withdrawn outright, two are narrowed, and three sub-claims are retracted. No new findings.

### Retained findings

**R1 (P2) — Pi `move_path` replaces an existing destination.** Accepted as reproduced. Stubbing only the Type dependency against the production-assembled module is the right evidence standard — it matches how the repo tests the extension and it exercises the shipped registration path, not a reimplementation. The fix stays minimal: `lstat(to)` and refuse with the host's wording. Two precision notes, neither of which justifies more machinery:
- Use `lstat`, not `stat`. A dangling symlink at the destination must also be refused; `rename` replaces the link.
- A naive existence check will also refuse a case-only rename on Windows (`enemy.gd` → `Enemy.gd`), because the destination resolves to the source. That is an acceptable limitation if documented, or compare file identity first. Do not build a transaction or close the TOCTOU window; this is a single-agent cooperative tool.

This is a Pi-only divergence — the GDScript host already refuses — so the fix lands in one place.

**R2 (P2, contested) — `git_diff` advertises `path` and ignores it.** I accept P2, and I retract two parts of my round-2 framing:
- **Retracted:** "hides staged changes." Pi documents unstaged-only at `gamesmith-extension.ts:242`, and the host description promises only workspace changes. My staged-omission argument assumed HEAD semantics that were never advertised. It is not a defect in either surface.
- **Retracted:** prescribing `git diff HEAD`. That changes the tool's semantics and has an unborn-HEAD failure mode. The minimal fix keeps the existing diff base and adds the pathspec: `git diff -- <path>`. The path must pass through the same workspace validation as the other file tools; otherwise `../..` becomes an out-of-workspace read even with argument-array invocation.

Severity rationale: the schema is a contract with the model, and the diff is the model's own acceptance evidence. Under the 50 KB transport bound, an unscoped diff can silently omit the file that was asked about, and the model then reasons from wrong evidence about whether its edit landed. That is verification integrity, not cosmetics — hence P2. If the project's rubric reserves P2 for state corruption or user-visible data loss, P3 is defensible and I will not argue further; this is a rubric disagreement, not a factual one. Removing `path` from the schema also resolves the contract violation, but leaves multi-file truncation as a separate pre-existing limitation.

**R3 (P3) — recursive delete crosses a nested `.git`.** Accepted, and my round-2 description was wrong in one respect: this is a *complete, silent* deletion, not a partial one. `WorkspaceOps.delete_path('vendor')` returns `ok:true` after removing `vendor/.git`, while direct mutation of the same path is refused. That is a reserved-path promise applied at the entry point and not to descendants. P3 is right on reachability: the shipped tool surface cannot create a nested `.git`, so this is outside-tool/player territory. Fix: refuse the operation, or skip and report the preserved entries — a silent skip is worse than either, because the caller believes the tree is gone. No rollback required; I accept that tree deletion is not transactional.

**R4 (P3) — hidden entries defeat recursive delete with a misleading error.** Accepted as reproduced and split from R3. The defect is not partial deletion per se — it is that the failure is attributed to an open file and the caller is told to stop the game and retry, which cannot fix enumeration. `include_hidden = true` before enumeration is the fix. This is GDScript-only; Node's `rm -r` does not skip hidden entries, which is consistent with the host's probe. I drop the read-only retry and the "error does not inventory what was removed" complaint; the actionable part is the wrong remediation advice.

### Withdrawn

**OpenCode evidence gap and `?? '.'` fail-open — withdrawn entirely.** My finding rested on the acceptance script not being wired into release verification. `verification-plan.mjs:112` resolving `acceptance:opencode-permissions`, plus the README's explicit opt-in contract, refutes that premise. The `?? '.'` default is only a defect if a supported CLI version omits a path key for a tool where omission does not mean cwd; the acceptance script tests exactly that for read/write/edit/glob/grep on 2.1.2. Key drift without an upstream change is speculative. The only residual is a coverage limit: the deterministic suites do not exercise the real CLI, so an upstream change is caught only by rerunning opt-in acceptance — which is the documented contract, not a gap.

### Unscored follow-up

The `cmd.exe` percent-name concern stays unverified and unscored, but I do not accept "harmless because the name is player-supplied." If it reproduces, Pi's cwd moves outside the game directory, which is confinement-relevant regardless of who typed the name. The reproduction is cheap and decisive: name a game `%TEMP%`, start Pi, and ask it for its cwd or run a relative-path tool. If confirmed, the minimal fix is to stop interpolating the path into a `cmd` command line — spawn with `cwd`, or escape `%` as `%%` if the `.cmd` shim forces `cmd`. If it does not reproduce, close it.

### Remaining disagreement

Only R2's severity, and it is a rubric question rather than an evidentiary one. Everything else is substantive agreement, including the corrections to my round-2 overstatements: no staged-diff defect, no HEAD prescription, no partial-deletion claim for nested `.git`, no `MetadataStore`-as-proof framing, no read-only retry, and no OpenCode finding.

**Final retained set:** one P2 (Pi move overwrite), one P2-or-P3 by rubric (diff `path` ignored), two P3 (nested `.git`, hidden-entry deletion), one unscored follow-up (`cmd` percent). No P1. Coverage limits from round 2 stand unchanged: no full suite, no provider acceptance, and the unread-file list remains a limit rather than a clean bill.

### Host final decision

Accept R1-R4 as stated above, including P2 for R2 because silently ignored scope affects a shipped tool contract. Withdrawn claims stay withdrawn. No factual or severity disagreement remains in the retained set. Stop at round 3; further architecture or speculative findings are outside the evidence.

Round-2 and round-3 prompts were checked to end with the exact requested sentence:

> you can agree or disagree with everything, also be wary of speculative over-engineering
