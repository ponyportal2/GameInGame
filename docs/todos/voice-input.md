# Voice input, phase one

- [x] Add failing worker and gameplay submission regressions.
- [x] Local Whisper worker with cached selectable models outside the repository.
- [x] Microphone toggle, transcript HUD/editor, explicit send and optional auto-send.
- [x] Preserve gameplay input, chat drafts and admission/rejection semantics.
- [x] Verify source, rendered UI, real local recognition and rebuilt package separately.
- [x] Prepare tested source and the rebuilt Windows package for delivery.

Scope: focused-window shortcuts, local batch recognition, no TTS or always-listening
mode. Default multilingual `base`, CPU/int8. Model downloads and the optional
Python environment belong under `user://host/voice`, never in the project.

References: [Hermes](https://github.com/NousResearch/hermes-agent/blob/main/tools/transcription_tools.py),
[faster-whisper](https://github.com/SYSTRAN/faster-whisper),
[Godot microphone capture](https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html).

Usage and limitations: [Voice input](../voice-input.md).

## Verification, 2026-11-03

TDD began with missing-worker and missing-host-controller failures. Tests use
production code with deterministic inference/capture fixtures, plus actual
worker subprocess IPC. They cover model caching/selection, language, silence,
invalid/long audio, inference failure, transcript bounds, WAV cleanup, stop/parent
exit, recording limits, focus loss, stale game results, admission, busy/rejected
drafts, optional auto-send, separate typed/picture drafts, gameplay ticking,
mouse/focus preservation, settings, and minimum-size layout.

- Final explicit source/package/windowed selection: **16/16 entries passed**,
  14 selected tests, no failures/reuse/skips, 183.8 seconds.
  `%TEMP%\gamesmith-verify-hdQ2oh\results.json`.
  Includes voice/verification/Pi-pin Node contracts, voice/chat-picture/annotation/
  history/layout/library/settings/detached-chat host suites, package contents/
  structure and rendered acceptance. Source voice fixture: **31/31 assertions**.
- A final testing-only refinement fingerprints Python for voice-only verification.
  Its regression failed first, then Node voice + verifier contracts passed:
  **3/3 entries**, 30.9 seconds.
  `%TEMP%\gamesmith-verify-gwst7m\results.json`.
  The Node voice wrapper executes **nine Python tests**, including real worker IPC.
- Actual windowed microphone capture: **34/34 assertions** in the earlier source
  fixture (`%TEMP%\gamesmith-voice-microphone-A856eW\engine.log`). Checks real PCM
  duration, muted capture bus and restored routing; this does not establish
  recognition accuracy from a human microphone recording.
- Actual local inference, private Python 3.12 environment and downloaded weights
  outside the repo: **base** and **tiny** both recognized the Windows SAPI English
  sentence “Make the enemies faster and change the grenades to red.” Base took
  7.19 seconds on its first cached-model load, then 0.72 seconds warm; tiny's first
  download plus inference took 21.36 seconds. This is a short acceptance sample,
  not an accuracy or latency benchmark. Evidence:
  `%TEMP%\gamesmith-voice-acceptance-d15f6076a8b54a49b3d26a7f2a3c3e02\recognition.json`.
- Real base inference through Godot's production controller/worker IPC passed
  **33/33** (`%TEMP%\gamesmith-voice-ipc-r417ux\engine.log`). This replays a WAV
  rather than depending on physical speech into the microphone.
- Rebuilt PCK launched from an isolated directory outside the checkout:
  **38/38 assertions**, including real worker extraction/inference, actual
  microphone capture, UI/draft/gameplay contracts and installation navigation.
  `%TEMP%\gamesmith-voice-packaged-AZFTqN\engine.log`.
  Gameplay/chat/settings screenshots captured there were visually inspected.

Earlier focused UI selection had four passing tests and one layout-fixture
failure because it assumed five settings tabs. Updating that assertion for the
Voice tab and rerunning failed-only passed; the final broader run above is green.

The first actual dependency install exposed the upstream PyAV 19 incompatibility
with faster-whisper 1.2.1 (`metadata_errors` removed). Installation now constrains
`av>=11,<19`; reinstall and both real model checks passed. See
[upstream issue](https://github.com/SYSTRAN/faster-whisper/issues/1589).

No full deterministic suite or real coding-provider calls were run for this
feature. Recognition was local; downloaded models, the private environment and
test audio remained outside the repository. The optional environment is not
installed into the player's ordinary app data by these tests.
