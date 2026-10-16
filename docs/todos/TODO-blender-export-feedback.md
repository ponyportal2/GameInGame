# Blender export feedback

- [x] Preserve bounded, deduplicated warning summaries independently of log tails.
- [x] Add advisory checks for connected procedural/custom material graphs, without treating white materials as errors.
- [x] Extend the reusable example with a tested generated image texture and document export and multi-view recipes.
- [x] Disable backup blend files in private Blender jobs.
- [x] Verify warning/status regressions and real Blender-to-Godot material import, rebuild and check the Windows package.
- [x] Record evidence and limitations; commit and push without dispatching CI.

Keep script-owned render settings. Material checks are advisory, not an exhaustive glTF validator or a substitute for inspecting the imported game.

## Verification

- Focused development run: `C:/Users/User/AppData/Local/Temp/gamesmith-verify-HgpQyO/results.json` (Node Blender 19/19, host Blender 130/130).
- Real source Blender/Godot: `C:/Users/User/AppData/Local/Temp/gamesmith-verify-HvDmRw/results.json`, 35/35 assertions. The first run (`gamesmith-verify-95amFb`) failed one color assertion because it sampled unused black UV-atlas space; the regression now samples actual mesh UV triangles. No bake/gamma workaround was required.
- Covers embedded baked texture dimensions and colors, disconnected/white/procedural material cases, warnings outside the retained log, multiple previews, repeated-save backup suppression, headless/rendered Godot import, Stop and owned-orphan cleanup.
- Final focused/package run: `C:/Users/User/AppData/Local/Temp/gamesmith-verify-XjoxqK/results.json`, 8/8 steps passed, no reuse/failed/blocked/interrupted steps and inputs unchanged: rebuilt Windows PCK, Node Blender 19/19, host Blender 130/130, game assets 10/10, runtime assembly 14/14, package contents and structure.
- Packaged real Blender/Godot: `C:/Users/User/AppData/Local/Temp/gamesmith-packaged-blender-jUmVoY/results.json`, 35/35 assertions; PCK SHA-256 `edc966e585e1202baba04cf8d9a4ad9e378c2c706cfd1d7f649a4b0789dc976d`.
- Evidence annotation added after those frozen runs; executable/runtime sources did not change afterward. The full unrelated harness/release suites were not repeated for this Blender-only change. No GitHub CI was dispatched.

Material findings are hints from the live scene, including preview objects, not an exhaustive exporter validator. Script-owned render and emission settings are unchanged. This work does not claim a Python sandbox or close the previously documented imports/spawn-persistence limitations. No model/provider calls are needed for these Blender/Godot checks.
