# Optional Blender per game

- [x] Add an unchecked creation option and a per-game Settings toggle; retain existing games' Blender availability.
- [x] Omit disabled Blender tools/descriptions and generated instructions across harnesses; reject direct disabled calls.
- [x] Cover creation, later enable/disable, persistence, runtime tool catalogs and prompt behavior.
- [x] Verify shared consumers, rebuild Windows package and record evidence.
- [x] Commit and push intended files; verify remote revision and preserve unrelated scratch files.

Blender availability is separate from the existing global automatic script approval setting. Availability changes wait until the agent and Blender are idle. Existing conversation history may still mention Blender after disabling it, but new instructions/tool catalogs omit it. Codex cannot replace a saved thread's dynamic tools: changes require explicit confirmation to archive its session reference and start a fresh Codex conversation, preserving chat/files. Other sessions are resumed normally.

## Verification

- Full affected coverage: `%TEMP%/gamesmith-verify-bZN4Nc/results.json`, 77 steps passed and one failed. The failure was 12 source assertions expecting the old literal `_game_prompt()` call; those now accept its per-game argument. All other shared consumers, lifecycle suites, package checks and launcher tests passed. The result records one skipped Node assertion.
- Failure-only rerun with a fresh Windows package build: `%TEMP%/gamesmith-verify-Q8tJWd/results.json`, 3/3 steps passed. Blender host 158/158 includes disabled direct `blender` and `authorize_blender` calls across all harnesses, along with existing approval/grant behavior.
- Final rebuilt-package contents/structure checks: `%TEMP%/gamesmith-verify-HXqKGV/results.json`, 3/3 steps passed. No runtime sources changed afterward; this evidence annotation was added after completion.
- Node Blender 27/27 covers real Pi extension registration with a schema-builder stub and enabled/disabled assembled MCP catalogs; Command-code registration/policy 2/2. Settings host 48/48 covers creation, persistence, later enable/disable, runtime retirement, legacy compatibility and explicit Codex archive confirmation/cancellation.
- Minimum-window layout failure-only rerun: `%TEMP%/gamesmith-verify-r96MXB/results.json`, 2/2 steps passed. Earlier layout runs (`vqfxs4`, `GrGUlw`) exposed off-screen Create/Cancel buttons; shortened harness help and tighter spacing fixed this. Full affected coverage subsequently passed the layout suite too.
- An earlier development run (`TBVZxb`) was interrupted after the new Command-code fixture omitted its prompt path; the fixture was corrected before the full run. No live provider calls or GitHub CI. Unrelated `tools/fake-openai-endpoint.zip` remains untracked and untouched.
