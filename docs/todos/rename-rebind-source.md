# Renaming the open game rebinds the loaded source

Status: done (2026-10-20)

## Problem

`GameRunner` records the path it loaded (`active_source_path`) and the
dependency files it collected. `_rename_game` moved the workspace and updated
`current_game`, `tools.workspace`, the test supervisor and the runtime log, but
not the runner. `_on_load_success` compares the recorded path with
`store.game_path(current_game).path_join("main.gd")` to decide whether the live
game is the workspace copy:

- the status label fell back to "Running last working snapshot", and
- `store.save_working_snapshot()` was skipped, so after a rename the game stopped
  promoting new working snapshots until it was closed and reopened — the
  "last working" fallback silently stayed at the pre-rename content.

## Fix

- `GameRunner.rebind_workspace(old, new)` rewrites `active_source_path` and
  every `dependency_paths` entry that lives under the old workspace.
- `_rename_game` calls it after a successful rename of the open game.

## Evidence

`tests/library_actions_runner.gd` creates a game with a `main.gd`, opens and runs
it, renames it through the UI handler, and checks the recorded source moved:

```
# before
ERROR: renaming the open game rebinds the loaded source
FAILED: {"passed":1,"failed":1,...}; 22.3s

# after
PASSED: {"passed":2,"failed":0,...}; 21.9s
package suite with --build-package PASSED: {"passed":4,"failed":0,...}; 89.5s
```
