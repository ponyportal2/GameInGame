# Workspace link and Git-metadata boundary

- [x] Regress linked reads, writes, deletes, moves and listings.
- [x] Refuse reserved `.git` mutations from host file tools.
- [x] Remove and skip links instead of following them during tree deletion/copy.
- [x] Focused host verification; record evidence and limitations.

## Changes

`GameTools` validates containment lexically today, which is not enough: a
symbolic link or Windows junction inside the workspace can resolve outside it.
Every file tool now walks existing path components with `DirAccess.is_link` and
rejects a link in any position (`read_file`, `write_file`, `patch_file`,
`list_files`, `delete_path`, `move_path`). Recursive listing and search skip
linked entries instead of recursing into or reading through them. Mutations also
reject any `.git` path component so repository metadata stays under the Git
tools, matching the Node bridge policy.

`MetadataStore._remove_tree_abs` removes a link entry itself instead of
recursing into its target, and `WorkspaceStore._copy_tree` skips links, so
deleting a game or saving a working snapshot cannot destroy or duplicate content
outside the game directory.

## Verification (2026-10-20)

- RED: `%TEMP%/gamesmith-verify-Yl5MPR/results.json` — `host:test` failed with
  143 assertions passed and ten failures covering `.git` writes/deletes/moves,
  reads/writes/deletes/moves through a link, listing a linked directory, a
  deleted outside file, and tree removal following the link.
- GREEN: `%TEMP%/gamesmith-verify-QIBnbg/results.json` — `host:test` passed with
  153 assertions, including junction creation through `mklink /J` and the
  fixture's own cleanup.
- The same RED run reported `assertions.failed: 0` in `results.json` because
  host failures print as `ERROR: FAIL:`; the runner's status was still failed.
  Evidence counting is corrected in a follow-up change.

Limitations: the fixture creates a directory junction on Windows (or a
directory symlink elsewhere) and asserts creation succeeds rather than skipping.
File symlinks and hard links are not covered; hard links share content without a
link attribute and remain outside this check. This is a cooperative workspace
policy, not a sandbox for generated game code. No full-suite or packaged run was
performed for this change, and no real-provider calls or GitHub CI were used.
