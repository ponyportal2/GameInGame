# Blender settings transaction follow-up

- [x] Defer Codex archiving until confirmed prerequisite saves succeed; restore the active reference if the final game write fails.
- [x] Commit Blender/harness together; defer runtime retirement and success notice until commit.
- [x] Cover failed global/game saves, cancellation and successful apply.
- [x] Run focused lifecycle checks, rebuild/check Windows package, commit and push.

Scope: preserve existing confirmation and session semantics; no new settings framework. Global/provider settings retain their existing partial-save semantics.

## Verification

- Focused run: `%TEMP%/gamesmith-verify-cnoJGp/results.json`, 7/8 steps passed. Codex lifecycle 38/38, harness 530/530, reliability 92/92, Windows PCK build and package contents/structure passed. Settings initially had 100 passes and two failures: the new success assertions read RichTextLabel.text rather than appended content.
- Failure-only rerun: `%TEMP%/gamesmith-verify-cd3lZy/results.json`, 2/2 steps passed; settings 102/102 after switching the fixture to get_parsed_text(). Production sources and the rebuilt package did not change after the first run.
- Failure injection covers global settings on Pi/Codex, Pi credentials/provider metadata, and final game commits on Pi/Codex. It verifies exact active session preservation, no stranded archive, unchanged availability/runtime/chat, open settings for retry, actual archive rollback, and successful retry. Existing confirmation/cancellation checks remain.
- No live provider calls or GitHub CI. Unrelated tools/fake-openai-endpoint.zip is untouched.
