# Voice comments in the picture editor

- [x] Regress picture-editor dictation, F8/F9, auto-send and retained drafts.
- [x] Add an editable picture comment and route voice into it.
- [x] Verify focused source and rendered/package behavior.
- [x] Rebuild the Windows runtime for commit/push.

Keep ordinary gameplay dictation separate. Cancel picture dictation when its
editor closes so a late result cannot annotate another picture. Auto-send uses
the normal chat admission path; busy/rejected messages remain drafts.

## Verification

- Initial regression failed because the editor had no comment field (31 passed,
  one failed). The first implementation run also exposed fixture-only worker
  polling: synthetic recognition has no worker, so that UI fixture now disables
  its polling while exercising the real record/stop/result code.
- Focused source checks: **11/11 entries passed, 270 assertions**, including
  voice, annotations, picture/chat history, layout, windowed input ownership and
  rebuilt package checks. `%TEMP%\gamesmith-verify-hIFQxW\results.json`.
- Two initial rendered package runs failed because synthetic shortcut presses
  occurred after screenshot drawing, after the host's input poll. The fixture
  now injects on the next process frame; production behavior was unchanged.
- Final fixture/rebuild checks: **4/4 entries passed**, voice **49/49** and
  packaged contents **9/9**.
  `%TEMP%\gamesmith-verify-hWuS2M\results.json`.
- Rendered source with screenshot capture: **49/49**.
  `%TEMP%\gamesmith-picture-voice-source-LeX6k5\engine.log`.
- Final rebuilt PCK launched outside the checkout: **49/49**, including caption
  append/edit, F8/F9, full-message auto-send, busy/rejection retention, silence,
  errors and cancellation. Its screenshot was visually inspected at 1024×640.
  `%TEMP%\gamesmith-picture-voice-packaged-9gqvNy\engine.log` and
  `pictures\voice-picture-comment.png` in that directory.

Recognition results were deterministic fixtures for this UI change. No new
physical microphone/Whisper accuracy or coding-provider acceptance was run;
the existing local recognition backend and model installation are unchanged.
