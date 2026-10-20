# move_path never overwrites an existing destination

Status: done (2026-10-20)

## Problem

`GameTools.move_path` called `DirAccess.rename_absolute` without checking the
destination. Godot's rename replaces an existing file, so an agent that moved
`main.gd` onto `keep.txt` silently destroyed `keep.txt` and reported success.
The old comment assumed Windows would fail instead; the RED run below shows it
does not.

## Fix

`move_path` now refuses a missing source and a destination that already exists
(file or directory), returning `Destination already exists. Delete or rename it
first.` Behaviour is identical on every platform, and the tool description says
so for models that plan multi-step edits.

## Evidence

`tests/test_runner.gd` writes `keep.txt`, attempts the move, and checks both
files survive; it also covers a missing source and a move that creates a new
subdirectory.

```
# before
ERROR: FAIL: move refuses an existing destination
ERROR: FAIL: a refused move keeps the destination intact
ERROR: FAIL: a refused move keeps the source
FAILED: {"passed":1,"failed":1,...}; 41.4s

# after
PASSED: {"passed":2,"failed":0,...}; 40.8s
package suite with --build-package PASSED: {"passed":4,"failed":0,...}; 82.9s
```
