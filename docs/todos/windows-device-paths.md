# Workspace paths: reject Windows devices and trailing dots

Status: done (2026-10-20)

## Problem

Both path guards resolved a relative path lexically and by realpath, but neither
rejected names Windows treats specially:

- `CON`, `NUL`, `AUX`, `COM1`–`COM9`, `LPT1`–`LPT9` open as devices, with or
  without an extension (`nul.txt`, `aux.gd`), so a tool call could write to the
  console or block while reading it instead of touching a game file.
- Windows silently strips a trailing dot or space from a segment, so `notes.`
  and `notes` address the same directory even though the guard sees two.

## Fix

- `tools/pi/workspace-paths.mjs` (the module every harness assembles as its
  `workspace-paths.mjs`) rejects any segment that ends with `.` or ` `, or whose
  name before the first dot is a reserved device. `.` and `..` are exempt
  because containment already handles them. Gated on `process.platform`.
- `PathUtils.safe_relative_path` applies the same rule through the new
  `_is_windows_device_path`, gated on `OS.get_name() == "Windows"`.

## Evidence

`tests/workspace-paths.test.mjs` adds a Windows-only case that rejects
`CON`, `nul.txt`, `aux.gd`, `sub/CON.gd`, `dir./x.gd` and `name /x.gd` while
still accepting `main.gd`.

`tests/test_runner.gd` asserts the guard directly, because the tool layer
already refused these names for unrelated reasons and would not have proven the
new code:

```
# before the guard
ERROR: FAIL: path guard rejects CON
ERROR: FAIL: path guard rejects nul.txt
ERROR: FAIL: path guard rejects aux.gd
ERROR: FAIL: path guard rejects assets/CON.gd
FAILED: {"passed":1,"failed":1,...}; 41.4s

# after
PASSED: {"passed":2,"failed":0,...}; 41.3s
node:workspace-paths PASSED: {"passed":1,"failed":0,...}; 1.6s
package suite with --build-package PASSED: {"passed":4,"failed":0,...}; 83.1s
```
