# GameSmith verification workflow

Run the whole source verification stack with Godot 4.7.2:

```bash
GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

It performs, in order:

1. deterministic verification of root `GameSmith.exe`;
2. `tools/windows-bootstrap` Go unit tests when Go is available;
3. the fast headless Godot suite;
4. the real-window hostile generated-input regression under `xvfb-run` when available;
5. the fake OpenAI-compatible `/v1/chat/completions` acceptance workflow;
6. a real process-level migration check from the old `GameSmith Host` writable directory to `GameSmithHost`.

## Fake `/v1` acceptance workflow

`run-fake-v1-e2e.sh` starts `../fake-openai-endpoint/gamesmith-server.mjs` and drives the **production Custom-provider HTTP adapter** rather than injecting an in-memory provider.

The scripted server exercises:

- a false text-only `Done.` before any game files exist;
- real OpenAI-format file/Git/reload tool calls;
- initial 3D game generation and actual frame processing;
- a later patch/reload request;
- failed generated code followed by repair;
- malformed tool arguments;
- HTTP 500 and invalid JSON provider failures;
- a deliberately small configured action-limit failure over real HTTP;
- `reasoning_effort` and GameSmith tool-schema transport;
- a two-process restart where process #2 is rejected unless process #1's prior conversation is replayed.

The production **default** agent action limit is 150 and is tested in the fast/UI suite. The real-HTTP runaway fixture temporarily sets a small limit so CI does not waste 150 round trips proving the same termination branch.

The GameSmith-specific scripted server needs Node but no `npm install`. The rest of `tools/fake-openai-endpoint/` is the user-supplied fake OpenAI endpoint repository retained as protocol/testing reference material.

## Expected parse errors

Some verification cases deliberately write invalid generated GDScript. Godot will print parse errors for those candidates. The tests only pass when the host rejects the candidate, keeps/recovers the working game as expected, and continues the agent flow correctly.
