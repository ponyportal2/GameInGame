# Reload followed by Enter

- [x] Reproduce keyboard focus stealing Enter after gameplay Reload.
- [x] Fix input ownership without removing keyboard navigation in chat/settings.
- [x] Run focused host and packaged checks; rebuild and push.

Live `2d` log shows repeated successful loads (versions 2–17), rather than startup failures. Investigating gameplay Reload retaining GUI keyboard focus.

## Result

The clicked gameplay Reload button retained focus. Enter/Space activated its
`ui_accept` behavior again, consuming the input intended for the game's start
handler and reloading assets back into the title screen. Release host-owned
keyboard focus after manual gameplay Reload and when resuming gameplay; leave
game-owned focus and chat keyboard behavior intact.

## Verification

- Red: `%TEMP%/gamesmith-verify-iARtLL/results.json`: repeated Enter changed the
  load version and never reached the fixture's start handler. Four functional
  assertions failed. An additional new assertion incorrectly expected chat's
  Reload button to retain focus; corrected it to the existing chat-input focus
  contract. Intermediate fix run: 97 passed / that one test assertion failed.
- Final: `%TEMP%/gamesmith-verify-noEOer/results.json`: 13/13 steps passed,
  including package rebuild, reliability (99 assertions), UI layout, host core,
  chat history, reload settings, library actions, resource-cache regressions,
  script-loading policy, and package structure/contents.
- Actual `2d` packaged acceptance: `%TEMP%/gamesmith-reload-2d-acceptance/node-packaged.log`.
  Copied its current source and eight PNGs into an isolated application-data
  workspace. Eight checks passed: initial load/Enter, then three actual GUI mouse
  Reload / Enter cycles with unchanged load version after Enter and PLAYING state.
  Exit code 0. Headless injected GUI input, not physical keyboard/manual visual
  acceptance. The existing chat-history reader also logged an unrelated JSON
  parse diagnostic for the empty EOF line; it did not affect these checks.
- Live `2d` workspace left unchanged; no model/provider calls or GitHub CI.
