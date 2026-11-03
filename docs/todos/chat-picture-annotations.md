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

## Review follow-up

- [x] Bound draft/history preview textures and avoid retaining flattened drafts.
- [x] Use lightweight attachment availability and direct preview decoding.
- [x] Regress Escape during capture and normalize temporary evidence paths.
- [x] Measure sparse long diagonals at 1440p/4K before changing rasterization.
- [x] Run focused source/rendered/package verification and record results.

Drafts keep the original and strokes for editing, the PNG identity and a preview
texture bounded to 110 by 56 pixels. History textures fit within 320 by 320 pixels,
including tall screenshots. Previews preserve aspect ratio without upscaling;
saved PNGs retain full resolution. Send admission checks identity, readability
and file size without decoding; agent delivery still validates the PNG. History
decodes once, without a base64 round trip. Capture consumes keys until the frozen
frame is ready, keeping Escape from restoring gameplay input prematurely.

The sparse-diagonal benchmark demonstrated an actual hitch: **544.8 ms at
2560 by 1440** and **1494.0 ms at 3840 by 2160** for one segment. Restricting each
rasterized row to the brush's reach reduced those measurements to **11.3 ms** and
**20.1 ms** on this machine. The rasterizer and antialiasing remain the same;
27 small pixel-for-pixel comparisons against the original algorithm cover stroke
directions, dots, fractional coordinates/widths, transparency and edge clipping.
Timing is diagnostic, not a machine-dependent pass threshold.

Review verification (deterministic fixtures; no provider calls or GitHub CI):

- Initial regressions reproduced the issues in all three selected runners.
  Evidence: `%TEMP%\gamesmith-verify-cEQwwP\results.json`.
- Focused verification after fixes: **11 passed / 1 failed**, 147.6 seconds,
  including package build/import. Source annotation/store assertions: **78/78**;
  picture UI: **29/29**; rendered input: **43/43**. Also covers history, layout,
  library navigation, settings, image transport and execution from the PCK.
  The sole failure was the sandbox blocking Python startup (`spawn python EACCES`)
  for package structure. Evidence: `%TEMP%\gamesmith-verify-VCCqft\results.json`.
- Approved failed-only rerun outside the sandbox: **1/1 passed**, 1.6 seconds.
  Evidence: `%TEMP%\gamesmith-verify-Cgb5Kw\results.json`.
- Direct execution of `chat_picture_ui_runner.gd` from the rebuilt PCK with
  isolated user data and a working directory outside the source tree:
  **29/29 assertions passed**.
  Evidence: `%TEMP%\gamesmith-packaged-picture-review-51078c6160cc4edcbeed86eec11c790a\engine.log`.

## Original verification

TDD started with failing canvas/store and UI-admission regressions before their
implementation (`gamesmith-verify-yK9GsF` and `gamesmith-verify-ahw6wg`).

- Focused source run: **9/9 entries passed**, 91.4 seconds. Covers annotation,
  chat UI/history, existing host/UI regressions, all 14 assembled tool catalogs,
  image response transport beyond the text-output cap and rendered input.
  Evidence: `%TEMP%\gamesmith-verify-zw5KwS\results.json`.
- Exhaustive affected run: **110 passed / 1 failed**, 1269.7 seconds, 109 selected
  tests plus package build/import. The sole failure was the selector regression's
  stale expected consumers for `game_tools.gd`. All production, native lifecycle,
  recovery and package checks passed. New source fixtures: **39 annotation/store
  assertions and 18 chat UI assertions**, zero failures.
  Evidence: `%TEMP%\gamesmith-verify-yIMDTg\results.json`.
- Corrected that expected consumer list; failed-only rerun: **2/2 entries passed**,
  27.0 seconds. No production changes after the exhaustive run.
  Evidence: `%TEMP%\gamesmith-verify-kiQPgK\results.json`.
- Final rendered acceptance and README pin contract: **3/3 entries passed**,
  8.6 seconds. Real Ctrl+Shift+S and mouse drawing, clean capture without host
  controls, marked PNG pixels, Cancel input restoration and draft preservation.
  Evidence: `%TEMP%\gamesmith-verify-0ymYIv\results.json`.
- Packaged `chat_picture_ui_runner.gd`, executed with the bundled Godot against
  the rebuilt PCK in isolated user data: **18/18 assertions passed**.
  Evidence: `%TEMP%\gamesmith-packaged-pictures-81c66827dae94aa89cb1feb12dd7f53a\engine.log`.
- Manually inspected rendered editor and queued-picture screenshots from the
  focused run. Package contents also execute pen flattening, PNG save and
  `inspect_attachment` against the shipped PCK.

No real-provider invocations or GitHub CI were used. Initial prompts carry text
and opaque PNG references; existing image-capable tool responses deliver the PNG
when the agent calls `inspect_attachment`. No arbitrary filesystem access was
added. These checks validate the application and transport; they do not claim
that every model will interpret a picture correctly.
