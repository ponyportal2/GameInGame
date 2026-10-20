# Workspace naming and deletion safety

- [x] Regress hidden, reserved, trailing-dot and control-character names.
- [x] Keep metadata when a workspace cannot be removed.
- [x] Terminate partial JSONL tails before appending.
- [x] Focused host verification; record evidence and limitations.

## Changes

`sanitize_game_name` now removes leading dots (the library skips hidden
directories, so a dot-prefixed workspace existed but was never listed),
strips trailing dots and spaces that Windows silently drops, rejects DEL in
addition to C0 controls, prefixes Windows reserved device names (`CON`,
`PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`, including names with an extension),
and trims edges again after the 64-character cut so truncation cannot leave a
trailing dot or space. Interior dots and ordinary names such as `Console` or
`auxiliary` are unchanged.

`WorkspaceStore.delete_game` removes the workspace before its metadata. A
failed removal (for example an open file on Windows) now keeps the metadata so
the game remains listed and deletion can be retried; previously the metadata
was deleted first and the workspace became an orphaned, unlisted directory.

`JsonStore.append_json_line` terminates a partial final record before writing,
matching `ChatHistory.append`. A process killed mid-append previously merged
the next record into the truncated line, losing both.

## Verification (2026-10-20)

- RED: `%TEMP%/gamesmith-verify-IRJ5P3/results.json` — `host:workspace_store`
  failed with 23 passed, 15 failed before the source changes.
- GREEN: `%TEMP%/gamesmith-verify-EoHOaE/results.json` — 41 assertions passed.
- Focused selection
  `--test host:workspace_store,host:test,host:library_actions,host:reliability,host:chat_history`:
  `%TEMP%/gamesmith-verify-8C3lNC/results.json` — 6 entries passed, zero
  failed, 303 assertions, 179.6 seconds.

Limitations: the fixture overrides `_remove_tree` to simulate a locked
workspace instead of holding a real Windows file lock. Naming rules follow
Windows restrictions for every platform so a game can be moved between
machines; no full-suite or packaged run was performed for this change, and no
real-provider calls or GitHub CI were used.
