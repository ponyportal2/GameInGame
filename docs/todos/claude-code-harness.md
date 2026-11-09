# Claude Code harness

- [x] Inspect installed native CLI and define a bounded integration contract.
- [x] Add failing assembled-runtime protocol/launch/session regressions.
- [x] Register Claude Code through the harness inventory and production controller path.
- [x] Implement native streaming, explicit resume/reset, Stop, and GameSmith-only MCP tools.
- [x] Exercise deterministic controller/recovery/approval and packaged consumers.
- [x] Run installed CLI acceptance with its configured model; record limitations separately.
- [x] Rebuild Windows package/launcher and document setup.

Scope: integrate the installed `claude` CLI directly using its documented
streaming JSON transport. Reuse bounded workspace/MCP tools and existing host
approval controls. Native authentication, model and compaction remain Claude's.
No extra ACP adapter, SDK dependency, or controller hierarchy redesign.

## Verification

- TDD: the launch contract initially failed because Claude was absent from the production inventory. Assembled worker tests subsequently exposed a missing final-text correction flag; implementation now reports corrected completions through the common transcript path.
- Initial focused run: **7 passed / 2 failed**, 154.1 seconds (`%TEMP%/gamesmith-verify-3D25TB/results.json`). Failures were a stale recovery-count assertion and the new fake CLI executing tools before request admission. The real CLI had already passed that path. The fixture now waits on the real operation state, and its path-rejection assertion requires an actual workspace error rather than accepting any MCP error.
- Failed-only rerun: **3/3 entries passed**, 61.5 seconds (`%TEMP%/gamesmith-verify-7ro4Ks/results.json`). New first-tool admission regression is included in the final deterministic selection.
- Real provider, assembled adapter: installed **Claude Code 2.1.317** passed native writes, an outside-read attempt, same-backend history, explicit resume, Stop and continuation (`%TEMP%/gamesmith-claude-live-LCM7DP`). The configured native model was **deepseek/deepseek-v4.1-flash-1017**, without model/auth overrides. This is paid/native-provider evidence, separate from fixtures; the outside-read attempt alone is not an independent assertion of the returned native error contents.
- Real provider, production host UI/controller: **2/2 entries / 12 assertions passed**, 36.2 seconds (`%TEMP%/gamesmith-verify-2VmFNW/results.json`). Created main.gd, started/read/stopped a detached test, streamed text, waited for reload consent, completed mandatory preflight/live load, stopped another pending reload, and resumed the same native history. No global settings were edited. This uses the full generated GameSmith system prompt, rather than the small adapter-only acceptance prompt.
- Final exhaustive deterministic run: **120 selected / 122 entries passed; 5,565 assertions; zero failures, skips or reused results**, 1,540.1 seconds (`%TEMP%/gamesmith-verify-JA3HDh/results.json`). Includes all 16 harness consumers, Claude's 9 native-protocol cases, 52 controller assertions, 7 recovery assertions, package contents/structure, and Go launcher tests. No provider calls are part of this run.
- Rebuilt-PCK Claude lifecycle: **52/52 assertions, exit 0** (`%TEMP%/gamesmith-claude-package-0de741e2bc834138a928fabe3951d4fc/validated-results.json`). Uses the production packaged runtime and an external copy of the lifecycle runner with only its fixture path redirected. An earlier direct PowerShell launch did not wait for the GUI executable and supplied no usable evidence; the recorded validated run uses Node process capture and a fresh isolated data directory.
- Real-provider moved-metadata probe: copied the acceptance runtime to a different metadata directory, resumed the same saved native session, and recovered `ORBIT_CAT` (`%TEMP%/gamesmith-claude-moved-S2G2Nz`). This verifies native history across a directory move, not an end-to-end UI rename.
- Windows launcher rebuilt. Tested PCK SHA-256: `e7041cc09af167ff559f88b1ccad57e8c16d76f74e5f1eb7f9ebe4ac198921f5`; launcher SHA-256: `2d21682839c4541da91da0f4d5aea16262178522e6d419d37d3b9f7393fd3d97`. No Claude binary, credentials, SDK, or model files are bundled. No GitHub CI was dispatched.
