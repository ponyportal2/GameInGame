# Voice review fixes

- [x] Regress disabled shortcuts, installation retry, rename drafts and microphone refresh.
- [x] Fix the four demonstrated issues without changing voice/input architecture.
- [x] Run focused source and rendered/package checks; rebuild the Windows PCK.
- [x] Record results, commit and push; verify remote revision.

The shortcut toggle now gates only keyboard polling; the explicit Send voice
button can still send an existing draft. Rename cancels in-flight recognition
without discarding completed draft text. Settings refreshes device enumeration
on opening and retains an absent selection with an unavailable label. Explicit
installation rebuilds an incomplete private environment using the selected
interpreter, leaves model downloads alone, and invalidates an old success marker
if reinstall fails.

## Verification

- TDD red: both selected suites failed against the old implementation. Python
  regressions caught environment reuse and stale success markers; the host
  reproduced disabled sending and draft loss on rename before reaching the
  not-yet-implemented microphone refresh helper.
  `%TEMP%\gamesmith-verify-aHFHgT\results.json`.
- Failed-only rerun after fixes: **3/3 entries passed**, source voice fixture
  **60/60 assertions**, and eleven Python tests (no dependency/model downloads).
  `%TEMP%\gamesmith-verify-D0JlxD\results.json`.
- Final focused selection: **14/14 entries passed**, **436 assertions**, no
  failures, skips or reused evidence; 172.2 seconds. Includes voice/verification
  Node contracts; voice, picture/chat history, annotations, layout, rename/library
  and reload-settings host suites; rebuilt package contents/structure; rendered
  input ownership. Source voice now has **62/62 assertions**, including empty
  microphone enumeration and reopening Settings with an absent saved device.
  `%TEMP%\gamesmith-verify-x16QSR\results.json`.
- Rendered voice UI: source **62/62** and rebuilt PCK **62/62**, zero failures,
  script errors or timeouts. Packaged run launched outside the checkout with
  isolated user data.
  `%TEMP%\gamesmith-voice-review-7a408da0f62f42cfb445d0819067f1e6\results.json`.

Installer retry uses controlled environment-creation/pip fixtures to exercise
failure, interpreter selection and marker handling without downloads or global
Python changes. Existing worker subprocess IPC is exercised with silent audio.
No new physical-microphone, Whisper accuracy, paid-provider, or full deterministic
suite run was needed for these bounded UI/installation changes.
