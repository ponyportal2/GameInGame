# Marked pictures in chat

- [x] Regress pen coordinates, flattened PNGs, attachment access and history.
- [x] Add frozen-frame editor with undo, clear, colors and width.
- [x] Add capture shortcut/button, editable queued thumbnails and captions.
- [x] Send private PNG references while keeping visible chat clean; retain rejected drafts.
- [x] Exercise rendered capture/input restoration and all shipped tool catalogs.
- [x] Rebuild package and verify; deliver with this commit.

Scope: freehand pen on a frozen game screenshot; multiple pictures per message.
PNG files live in per-game metadata. No native multimodal prompt migration,
node picking, arbitrary file access or drawing framework.

Use **Ctrl+Shift+S** or **Mark screenshot** while a game is running. Attach returns
to paused chat. Cancel returns to the prior play/chat state. A message accepts up
to eight pictures, each with a comment; click a queued thumbnail to edit it.
Sent PNGs remain available after reopening chat or renaming the game. Unsent
pictures are removed on removal, navigation to the library or application exit.

## Verification

TDD started with failing canvas/store and UI-admission regressions before their
implementation (`gamesmith-verify-yK9GsF` and `gamesmith-verify-ahw6wg`).

- Focused source run: **9/9 entries passed**, 91.4 seconds. Covers annotation,
  chat UI/history, existing host/UI regressions, all 14 assembled tool catalogs,
  image response transport beyond the text-output cap and rendered input.
  Evidence: `C:\Users\User\AppData\Local\Temp\gamesmith-verify-zw5KwS\results.json`.
- Exhaustive affected run: **110 passed / 1 failed**, 1269.7 seconds, 109 selected
  tests plus package build/import. The sole failure was the selector regression's
  stale expected consumers for `game_tools.gd`. All production, native lifecycle,
  recovery and package checks passed. New source fixtures: **39 annotation/store
  assertions and 18 chat UI assertions**, zero failures.
  Evidence: `C:\Users\User\AppData\Local\Temp\gamesmith-verify-yIMDTg\results.json`.
- Corrected that expected consumer list; failed-only rerun: **2/2 entries passed**,
  27.0 seconds. No production changes after the exhaustive run.
  Evidence: `C:\Users\User\AppData\Local\Temp\gamesmith-verify-kiQPgK\results.json`.
- Final rendered acceptance and README pin contract: **3/3 entries passed**,
  8.6 seconds. Real Ctrl+Shift+S and mouse drawing, clean capture without host
  controls, marked PNG pixels, Cancel input restoration and draft preservation.
  Evidence: `C:\Users\User\AppData\Local\Temp\gamesmith-verify-0ymYIv\results.json`.
- Packaged `chat_picture_ui_runner.gd`, executed with the bundled Godot against
  the rebuilt PCK in isolated user data: **18/18 assertions passed**.
  Evidence: `C:\Users\User\AppData\Local\Temp\gamesmith-packaged-pictures-81c66827dae94aa89cb1feb12dd7f53a\engine.log`.
- Manually inspected rendered editor and queued-picture screenshots from the
  focused run. Package contents also execute pen flattening, PNG save and
  `inspect_attachment` against the shipped PCK.

No real-provider invocations or GitHub CI were used. Initial prompts carry text
and opaque PNG references; existing image-capable tool responses deliver the PNG
when the agent calls `inspect_attachment`. No arbitrary filesystem access was
added. These checks validate the application and transport; they do not claim
that every model will interpret a picture correctly.
