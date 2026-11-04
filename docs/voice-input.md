# Voice input

Voice dictation uses local Whisper recognition, independently of the coding
harness. It is disabled by default.

1. Open **Settings → Voice**. Choose a Python executable (3.11 or 3.12 recommended)
   and click **Install local recognition**. Installation creates a private Python
   environment; it does not change global packages or harness settings.
2. Enable microphone shortcuts, choose your microphone/model/language, and save.
3. While playing, press **F8** to start recording and **F8** again to transcribe.
   The game keeps running. **Escape** cancels recording or pending transcription;
   losing window focus cancels recording. Recordings stop after 60 seconds.
4. Read the transcript in the gameplay HUD, then press **F9** to send it without
   opening chat, pausing, or releasing the game's mouse capture. Open chat to edit
   the separate voice draft or use the Record/Send/Clear voice buttons.

Record/send shortcuts are configurable. They apply while GameSmith has focus;
they are not operating-system global shortcuts. Voice sends only its transcript:
an existing typed draft and queued marked pictures remain untouched. A busy agent
or rejected message keeps the voice draft for an explicit retry. Further dictation
appends to an unsent draft. Changing games clears that game's voice draft and
cancels pending recognition.

In the **picture marking editor**, F8 records/stops dictation into that picture's
editable comment instead. F9 attaches the current picture and sends the complete
chat message, including typed text and other queued pictures. With auto-send
enabled, a successful transcription does the same. A busy agent leaves the editor
and comment open; a rejected send retains the attached pictures and message for
retry. The separate gameplay voice draft is preserved. Closing/attaching the
editor cancels unfinished picture dictation so it cannot reach another picture.

**Send automatically after transcription** is optional and off by default. It
never schedules a delayed send when the agent is busy.

The default model is multilingual **base**, using CPU/int8 to leave the game's
GPU available. Other choices are tiny, small, medium, large-v3, and turbo. Tiny
is faster; larger models require more RAM and processing time. Language options
are automatic detection, English, and Russian. Selecting a language can help
short utterances. CPU recognition still competes with gameplay for CPU time.

The first non-silent recording downloads the selected model, so it can take much
longer than subsequent transcriptions. Installation and first-model downloads
require internet access. Once cached, recognition is local. The worker reuses its
loaded model between recordings and exits after five minutes idle or when the
host closes. No audio is sent to a transcription provider; the resulting text is
sent to the selected coding agent only when submitted.

The environment, downloaded models, and temporary recordings live under
`user://host/voice` (on Windows, normally
`%APPDATA%/Godot/app_userdata/GameSmithHost/host/voice`). Temporary WAV files are
removed after recognition or cancellation. No model weights or Python packages
are bundled in the repository or Windows package.

This follows [Hermes's local faster-whisper approach](https://github.com/NousResearch/hermes-agent/blob/main/tools/transcription_tools.py).
It is batch dictation, not streaming recognition, an always-listening assistant,
or text-to-speech.
