# GameSmith verification workflow

Run the whole source verification stack with Godot 4.7.2:

```bash
GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

The workflow performs, in order:

1. deterministic verification of the root Windows folder;
2. `tools/windows-bootstrap` Go unit tests when Go is available;
3. the fast headless Godot host/core/UI suite;
4. the real-window hostile generated-input regression under `xvfb-run` when available;
5. real globally installed Pi **Part 1** normal-agent acceptance;
6. real Pi **Part 2** native-compaction acceptance;
7. real Pi **Part 3** legacy-import/runtime-removal acceptance;
8. a process-level migration check from the old `GameSmith Host` writable directory to `GameSmithHost`.

## Real Pi acceptance

`run-pi-e2e.sh` starts `../fake-openai-endpoint/pi-server.mjs` and drives the actual globally installed `pi` executable over GameSmith's production JSONL RPC path. The deterministic server speaks streaming OpenAI-compatible `/v1/chat/completions` and requires only Node's standard library.

CI pins `@earendil-works/pi-coding-agent@0.99.2`. For local runs you may point GameSmith at another explicit Pi executable with `GAMESMITH_PI_BIN`.

The phased runner can be invoked directly:

```bash
GAMESMITH_PI_TEST_PART=1 GODOT_BIN=/path/to/godot tools/testing/run-pi-e2e.sh
GAMESMITH_PI_TEST_PART=2 GODOT_BIN=/path/to/godot tools/testing/run-pi-e2e.sh
GAMESMITH_PI_TEST_PART=3 GODOT_BIN=/path/to/godot tools/testing/run-pi-e2e.sh
```

Part 1 covers production controller selection, missing-Pi diagnostics, generation/edit/reload/Git behavior, streaming assistant/thinking events, false-completion recovery, native retry behavior, action limits, provider-call pacing, and Pi session restart/resume.

Part 2 covers manual and threshold-triggered Pi-native compaction, `keepRecentTokens`, persisted native compaction entries, checkpoint delivery to the next provider request, normal no-op classification, and byte-stable session entries across GameSmith restart.

Part 3 seeds a pre-Pi readable transcript and proves that it is imported into an empty Pi session exactly once, that the current request is not duplicated into the imported legacy block, that restart does not re-import it, and that production no longer contains the deleted homegrown agent/provider/compaction sources.

The production default Pi turn limit is 150. Runaway fixtures use a deliberately small test limit so acceptance does not waste provider round trips proving the same host-policy branch.

## Expected parse errors

Some host/runtime tests deliberately write invalid generated GDScript. Godot will print parse errors for those candidates. The tests only pass when GameSmith rejects the bad candidate, preserves or recovers the previous working game, and continues correctly.
