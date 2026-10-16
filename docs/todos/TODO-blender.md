# Blender support

- [x] Add a shared asynchronous Blender CLI job tool, bounded logs, cancellation and image inspection.
- [x] Expose the tool and thin bpy instructions to every harness without enabling shell tools.
- [x] Test failure, path, cancellation and image-content behavior; run installed Blender to render/export/inspect a real asset.
- [x] Verify Godot can consume the generated asset; run host/harness regressions and packaged smoke tests.
- [x] Document setup, supported workflow and evidence; rebuild the Windows pack.

Evidence (Windows, 2026-10-16):

- Blender 5.2.2 LTS, build d13f752e3b9c, standard Windows installation.
- Initial TDD failed on the missing Blender module. Focused shared-tool/path/
  image tests then passed; all six assembled MCP variants deliver native image
  content. Command-code ModApi, Codex dynamic tools and OMP native host results
  have separate image regressions. Pi registers Blender in both its extension
  and explicit RPC tool whitelist. All fourteen controllers share the guide.
- Full final Node suite: 200 tests, 199 passed, one intentional native-provider
  skip, no failures. `%TEMP%/blender-node-final.log`.
- The opt-in real Command-code 1.82.1 test was then enabled separately. An initial
  cold readiness attempt failed before inference; the next run exposed the
  ModApi image shape mismatch that fixture tests had missed. Fixed native
  conversion to image.source; the repeated native boundary + mod suite passed
  2/2. It captured 38 real CLI provider requests against an isolated local mock,
  including the actual preview data URI, exact 19-tool schemas, resume,
  compaction and injected guard failure. No external model was used by this test.
- Source Blender host: 20/20; source real Blender acceptance: 12/12.
  `%TEMP%/gamesmith-tests-gz3lBq/`.
- Uninterrupted complete host suite: all 33 runners passed, exit 0.
  `%TEMP%/gamesmith-tests-SrNdVs/`. This run started before the final
  Command-code image conversion fix; the native boundary/mod tests above cover
  that final change, and the rebuilt PCK checks below use the final runtime.
- Windows PCK rebuilt; packaged content, 20/20 deterministic host checks and
  13/13 real Blender checks all exit 0.
  Final rebuilt pack: `%TEMP%/gamesmith-blender-final-_m9gfr45/acceptance.log`.
  Real runs save/reopen a blend, export GLB, CPU-render PNG, decode/inspect PNG,
  load the GLB in Godot without editor imports, pass a separate headless game
  test, report Python tracebacks, and terminate real Blender on Stop and shared
  controller retirement. The blue
  tower preview from the packaged run was visually inspected.
- No live model inference was run separately through every harness; transport
  fixtures exercise the shared tool/image paths, and actual Blender/Godot runs
  exercise the host. Vision still depends on native harness/model capabilities.
  Existing Codex threads require explicit reset to gain the new dynamic tool.
- Explicit bpy scripts execute Python with user permissions, not in a sandbox.
  No GitHub CI was started. Linux/macOS discovery exists but was not accepted
  live in this Windows run.
