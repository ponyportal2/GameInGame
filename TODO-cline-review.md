# Cline review fixes

- [x] Add failing permission regressions for unmatched/replayed IDs, native kinds and conflicting structured names.
- [x] Bind permissions and reload approval to current announced calls; retain Cline 3.0.70 compatibility.
- [x] Include every Cline runtime source and controller in package-content verification.
- [x] Run Node, lifecycle/live and packaged verification; rebuild, commit and push.

Compatibility: ACP's programmatic name is optional. Cline 3.0.70 does not emit it; its own translator supplies the tool name through the title and categorizes MCP tools as other. This remains a native-Cline compatibility assumption, not protection against a compromised ACP backend. A title-only permission request will no longer suffice.

Verification:

- TDD: the new permission tests initially failed because the call tracker was absent; all 72 Node tests now pass. Added protocol and real-worker regressions cover unmatched/consumed IDs, cross-turn replay, conflicting structured names, native tool kinds, changed input, completed calls and unannounced reloads reaching no approval bridge.
- Cline deterministic lifecycle and same-game ownership runners pass. Final lifecycle rerun covers manual/automatic reload, cancellation and five-second retirement at all three blocked stages.
- Live selected native free-model acceptance passes in the full rerun: actual editing, headless testing, streaming, backend reuse, native history after reopen, 65-second approval, successful reload, Stop and same-backend follow-up. The first live run failed its last Stop precondition because a reload permission was rejected; the cause was not captured in that run. A focused same-session test then passed two reload approvals and Stop/follow-up, followed by the complete successful rerun with temporary metadata-only permission diagnostics. No observed thought deltas; no remote CI claim.
- Rebuilt Windows PCK passes the expanded package-content runner from an isolated directory, structural Windows package verification, and packaged Cline MCP/headless/reload smoke. Shared runtime implementations remain checked in their original source folders; all seven Cline source modules and its controller are now checked explicitly.
- Evidence: %TEMP%/gamesmith-cline-review-node.txt, gamesmith-cline-review-host.txt, gamesmith-cline-review-host-final.txt, gamesmith-cline-review-live.txt (initial failed precondition), gamesmith-cline-review-stop.txt, gamesmith-cline-review-live-rerun.txt, gamesmith-cline-review-package.txt. Temporary diagnostics are removed from committed source. Untracked screenshots remain untouched.
