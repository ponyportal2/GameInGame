# Review follow-ups

- [x] Correct the launcher OpenCode installation command and rebuild it.
- [x] Separate development package verification from the factory's committed-package gate.
- [x] Exercise native OpenCode workspace/metadata/link permissions and resumed mode.
- [x] Correct the Cline update notes.
- [x] Run focused regressions and packaged verification; record exact outcomes.

## Changes

- Windows launcher recommends `npm install -g @opencode/cli@2.1.2`, matching the supported adapter. Rebuilt `GameSmith.exe`.
- Development verification tests rebuilt working-tree PCK bytes. `--require-committed-package` performs the final delivery check after tests; SoftFac enables it. Failed-only reruns retain this requirement. A real export regression proves development passes before commit, delivery fails after executing tests, and committing the package clears the gate.
- Native OpenCode 2.1.2 acceptance reproduced reads through an outside Windows junction despite native permission rules. Added a small native tool hook using existing workspace-path validation, including nested `.git` aliases. No replacement file tools or permissions framework.
- Native OpenCode tolerates plugin-load errors. The worker now requires a fresh workspace-bound load acknowledgement before admitting prompts and refuses missing/refused confined-agent selection. Failed initialization cleans up its acknowledgement and native backend. Kilo retains its existing configuration/protocol.
- The native permission check is an optional exact test, `acceptance:opencode-permissions`; deterministic full-suite users do not need an installed OpenCode. It exercises actual native tools and resumed native state using a localhost deterministic provider and isolated configuration/data.
- Cline notes now reflect the existing child-only `CLINE_NO_AUTO_UPDATE=1`; an independently updated global installation remains possible.

## Verification (2026-10-30)

TDD failures were observed for launcher guidance, unconditional uncommitted-PCK rejection, native junction confinement, and native plugin-load continuation before the corresponding fixes. Intermediate native acceptance attempts also exposed plugin entrypoint resolution; the assembled `server.ts` entry is now tested through the real CLI.

- Initial focused source/native run: **7/7 entries passed**, 44.5 seconds. `%TEMP%/gamesmith-verify-nuND8V/results.json`.
- Final broader run: **14/14 entries passed**, 189.4 seconds; no failures, skips or reused evidence. Includes rebuilt PCK, Godot import, OpenCode/Kilo Node contracts, worker rejection/Stop/cleanup, verification contracts, all 14 harness assemblies, OpenCode/Kilo host lifecycle, shared turn recovery, package structure/contents, Go launcher unit tests, and actual OpenCode acceptance. `%TEMP%/gamesmith-verify-l841bF/results.json`.
- Added root-search traversal assertions afterward: **2/2 entries passed**, 22.6 seconds (setup plus native acceptance). Both root grep and glob skip the external junction. `%TEMP%/gamesmith-verify-ArFTju/results.json`.
- Final launcher rebuilt with the repository's CI flags (`-trimpath -ldflags='-s -w -H=windowsgui'`); launcher unit and package structure checks then passed **2/2**, 1.6 seconds. `%TEMP%/gamesmith-verify-3kO0IW/results.json`.
- Standalone `go test ./...`, GUI launcher rebuild, and `git diff --check` passed.

Native acceptance used OpenCode **2.1.2** with a local deterministic provider, not an external model/account. It covers valid inside edits, outside/junction read/write/edit/new-file/search denial, repository metadata writes, root search traversal, hidden forbidden tools, resuming plan into confined build, and zero model requests when the guard fails to load. This establishes native tool-policy behavior, not an OS sandbox or a real model's judgment. No real-provider calls, full-suite run, GitHub CI, commit or push is claimed here.
