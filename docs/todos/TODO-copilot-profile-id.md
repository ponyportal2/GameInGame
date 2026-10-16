# Copilot profile identity

- [x] Reproduce user-profile shadowing with a precedence-aware fixture.
- [x] Use a unique runtime profile ID/name and verify exact selection before inference.
- [x] Verify creation, resume and Stop with fixture/lifecycle/live tests.
- [x] Rebuild and verify Windows package, record evidence and limitations.

Keep native model settings and the existing startup tool restriction unchanged. No GitHub CI runs.

Evidence so far:
- Pre-fix precedence-aware regression selected personal `gamesmith` profile: reproduced.
- Focused Node suite: 16 passed, 0 failed. Same-directory resume receives a fresh ID; exact agent mismatch fails before inference.
- Source lifecycle: 29 passed. Final isolated packaged lifecycle: 29 passed; package contents and Windows structural verification passed.
- Initial source live run exposed backend metadata losing the profile ID on native model updates. Added that event to the fixture, reproduced two failing tests, then fixed the metadata write and reran the Node suite successfully. That initial live run is not counted as a pass.
- Collision precedence is tested with an isolated fixture COPILOT_HOME. Real personal Copilot profiles and native model settings were left untouched.
- Final source live acceptance: 33 passed, 0 failed (gamesmith-tests-6UrTqa/engine-0.log). Final packaged live acceptance: 33 passed, 0 failed (gs-copilot-profile-final-l3jyo0wn/copilot_integration_runner.gd.log). Both retain exact history across reopen, rename and Stop, verify fresh profile IDs, and complete the 65-second reload approval wait. Native effective model: auto.
- Logs reside under the Windows temporary directory. No remote CI was started.
