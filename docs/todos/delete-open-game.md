# Deleting the open game must release the adapter first

Status: done (2026-10-20)

## Problem

`App._delete_game_confirmed` removed the workspace and only then called
`_show_library()`, which tears down the game runner and the agent. While the
agent runtime is alive it keeps the game workspace as its working directory, and
Windows refuses to remove a directory that a live process still holds. Deleting
the game that was currently open therefore failed, the app still returned to the
library, and the only message was "Could not delete the game. Close programs
using its files and try again." — the program holding the files was GameSmith
itself.

Reproduced with a throwaway runner: create a game, open it, complete one request
so the adapter is live, then call `_delete_game_confirmed()`.

```
PROBE idle busy=false rpc=true pid=21880
PROBE after delete: workspace_exists=true listed=true current=
```

## Fix

When the target is the open game, the handler now retires the agent runtime
(synchronous `restart_runtime`, which kills the adapter tree), closes the
runtime log writer, and runs `_show_library()` **before** deleting the files.
It then deletes and refreshes the library. Deleting a game that is not open
keeps the previous order.

## Evidence

`tests/library_actions_runner.gd` now opens a game, runs one fixture request,
asserts the adapter is live, and deletes it:

```
# before the fix
ERROR: deleting the open game removes its workspace
ERROR: deleting the open game removes it from the library
FAILED: {"passed":1,"failed":1,...}; 17.1s

# after
PASSED: {"passed":2,"failed":0,...}; 16.8s
package suite with --build-package PASSED: {"passed":4,"failed":0,...}; 93.2s
```
