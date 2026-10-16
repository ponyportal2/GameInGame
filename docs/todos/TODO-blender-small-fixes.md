# Blender warning and iteration fixes

- [x] Fix diagnostic phrase boundaries and cover real warnings plus identifier false positives.
- [x] Inspect public test/Blender Stop responses; remove only demonstrated excess without changing lifecycle states.
- [x] Measure serialized public Blender status using Scene2 records and deterministic running/failed fixtures.
- [x] Document saved-scene iteration, preview-only lights/cameras and early previews.
- [x] Run focused verification and record evidence and limitations.

No new progress, timing, approval, diagnostics or GLB-inspection protocols.

## Inspection evidence

Measured all seven retained Scene2 Blender records through `BlenderSupervisor.execute` with cached terminal records, then JSON-serialized the returned public objects. Running/failed cases are deterministic variants of those records, not captured live states. No Blender/model jobs were launched. Measurement script: `%TEMP%/gamesmith-blender-public-response-measure.gd`.

- Completed compact status and Blender Stop: 4,006–4,193 UTF-8 bytes; text-content envelope 4,467–4,652 bytes.
- Running fixtures: 3,152–3,325 bytes; envelope 3,491–3,662 bytes.
- Failed fixtures: 9,973–10,149 bytes; envelope 10,620–10,796 bytes (intentional larger failure log tail).
- Explicit details, default first page: 21,247–22,097 bytes; envelope 22,994–23,878 bytes.
- The envelope calculation includes JSON escaping of the text response, not harness-specific transport/session overhead. Compact status is modest; no Blender status or Stop changes are justified.
- Test-game Stop returned `_public(run)`, including the retained `action_result`; that can contain screenshot base64. Stop now omits only that field, retaining existing lifecycle states and leaving action retrieval unchanged. The inherited Pi bridge's deferred completion now uses the same Stop result rather than resending status. A 2 MiB deterministic screenshot-sized fixture exercises pending, repeated, exited and deferred bridge Stop responses and retained action access. Measured test response: 2,099,851 bytes before projection versus 2,662 bytes for Stop.
- The standalone measurement exited successfully but emitted environment log-file/certificate diagnostics; it did not run games or validate visuals.

## Verification

- Node Blender: `%TEMP%/gamesmith-verify-wy5nhw/results.json`, 20/20 tests passed, including assembled MCP consumers and positive/negative warning regressions.
- Test-process regression: `%TEMP%/gamesmith-verify-BzaQIf/results.json`, 69/69 assertions passed, including pending/exited/deferred Stop, real rendered screenshots, retained action access and shutdown contracts.
- Final shared-consumer/package run: `%TEMP%/gamesmith-verify-TNWj3v/results.json`, all 21 steps passed, no failed/blocked/interrupted/reused/skipped steps. Rebuilt Windows PCK, Blender host 130/130, chat-process 16/16, harness assembly 14/14, native harness lifecycle consumers, Kilo Stop, package contents and structure. Sources stayed unchanged during the run; this evidence annotation was added afterward.
- `git diff --check` passed. The guide's tweak example uses the existing example's object/material names, save API and selected-hierarchy export options. It was reviewed against the current recipe; the new documentation snippet was not separately executed in Blender.
- Initial sandboxed affected-suite attempt (`gamesmith-verify-bW0EkX`) was stopped after process-ownership inspection failed and unrelated Node harness fixtures stalled; its incomplete record is not a full-suite result. Rerunning the failed Node Blender test outside the sandbox passed. Remaining verification used explicit focused/shared-consumer selections outside the sandbox.
- First focused run (`gamesmith-verify-6HTI21`) passed Blender, chat, assembly and package checks but failed one existing bridge graceful-stop assertion: the process exited with code 0 and `stop_method=unconfirmed`. The failure-only rerun passed all 69 assertions. Shutdown semantics were not changed to hide this failure; it remains a limitation of the first run.
- No live provider calls or GitHub CI. No new real packaged Blender/Godot visual acceptance or broad release-suite claim. The rebuilt Windows package is included; the unrelated scratch archive remains untouched.
