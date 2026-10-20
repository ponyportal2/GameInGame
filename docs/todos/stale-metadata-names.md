# New games never reuse leftover metadata

Status: done (2026-10-20)

## Problem

`WorkspaceStore.create_game` only treated an existing *workspace* directory as a
name collision. Metadata lives in a separate root (`user://host/games/<name>` or
equivalent), so a deletion that removed the workspace but failed to remove the
metadata left a metadata directory behind. Creating a game with the same name
then reused that directory: the new game inherited the previous transcript,
harness sessions and working snapshot while its own `metadata.json` was
overwritten.

## Fix

`create_game` now bumps the suffix when either the workspace or the metadata
directory exists (`_name_taken`). The leftover metadata is left untouched so it
can still be recovered or deleted deliberately, and the new game starts clean.

## Evidence

`tests/workspace_store_runner.gd` creates a game, removes only its workspace to
simulate the failed deletion, and creates the same name again:

```
# before
FAIL: a new game never reuses leftover metadata
FAILED: {"passed":1,"failed":1,...}; 14.5s

# after
PASSED: {"passed":2,"failed":0,...}; 14.6s
package suite with --build-package PASSED: {"passed":4,"failed":0,...}; 82.0s
```
