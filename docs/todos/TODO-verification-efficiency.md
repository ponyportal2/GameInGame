# Verification and harness maintenance

- [x] Add unified portable verification, summary/errors/full views over identical evidence.
- [x] Persist authoritative results.json, atomic progress, bounded diagnostics and stall reporting.
- [x] Add conservative affected suites, failure reruns and explicit fingerprinted evidence reuse.
- [x] Consolidate existing entrypoints and bound concurrency; keep Godot processes isolated.
- [x] Declare harness inventory and canonical runtime module maps; consume mundane lists.
- [x] Share runtime assembly across production, packaging checks and fixture verification.
- [x] Extract small ACP session/failure helpers without merging native security policies.
- [x] Add meaningful regressions for orchestration, fingerprints, inventory and runtime parity.
- [x] Verify through the new runner, document commands, rebuild Windows package and prepare the push.

Contracts: output modes affect stdout only; exit/result state decides success, not ERROR grep. Full logs always persist. Live model calls are opt-in; Codex live acceptance must explicitly use gpt-6-luna. Preserve user screenshot/ZIP. No GitHub CI dispatch.

Final local evidence (2026-10-16):

```powershell
node tools/testing/verify.mjs --suite release --output errors --build-package
```

- Passed uninterrupted: 81 steps, zero failed/blocked/reused/skipped steps, 1091.5 seconds; inputs remained unchanged.
- Node: 36 files, 218 passed tests and one existing intentional native-provider skip.
- Host: all 37 isolated runners, including canonical assembly for all 14 harnesses.
- Packaged contents/structure and Go launcher tests passed. Windows launcher and PCK rebuilt.
- Installed Pi/local provider emulator: 140/140; migration: 1/1; windowed ownership: 29/29.
- Complete logs, diagnostics, progress and fingerprints: `%TEMP%/gamesmith-verify-ro5nfz/results.json`.
- No paid-provider acceptance calls or GitHub CI runs. This evidence is local, not a remote status check.
- This final evidence annotation is documentation only and was added after the frozen-tree run.
