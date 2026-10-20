# ds to main merge review

- [x] Refresh remote refs and identify the branch-only commits.
- [x] Review production changes and their recorded verification evidence.
- [x] Reproduce recursive deletion through a nested workspace junction using disposable files.
- [x] Run focused workspace, library, workflow, and runner checks.
- [x] Recommend merge groups and identify concrete holds.

Scope: review only; no merge or production fixes. The nested-junction deletion
gap predates ds, but remains unfixed by its new workspace-link safeguards.
Disposable reproduction: `%TEMP%/gamesmith-ds-review-287994f1bab746f2af49ad49aada873b`.
`delete_path("container")` returned `ok=true` and deleted the sentinel outside
the workspace through `container/escape` (a Windows directory junction).

Fresh verification: `%TEMP%/gamesmith-verify-WOkVF7/results.json`, passed,
7/7 entries, 277 assertions, 60.1 seconds. Selection: Godot import,
node workspace-paths/verifier contracts, host core/workspace-store/library-actions/
test-workflow. No failures, skips, or reused results. No provider calls or full
suite rerun. `git diff --check origin/main...ds` passed.

Recommendation: keep the 16 branch commits. Complete `77cf544` by making
`GameTools._remove_tree_abs` unlink nested links rather than recurse through
them, with a public `delete_path` regression, before merging the complete branch.
Other changes are focused and useful: detached actions/cursors/injection/input,
final-status race, library rename/deletion, names/metadata/move handling, log
redaction, and fixture/evidence corrections. The runtime copy workaround is
reasonable for the documented zero-copy failure; no general copy framework is
needed. Existing full-suite documentation predates the latest changes and is
not evidence of a fresh full run at current HEAD. Real-model latency reduction
and actual native OpenCode compaction remain unproven by deterministic fixtures.
