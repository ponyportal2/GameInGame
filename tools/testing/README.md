# GameSmith verification workflow

Run the whole source verification stack with Godot 4.7.2:

```bash
GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/testing/run-verification.sh
```

For Windows or Linux, the portable runners isolate application data under a temporary directory and print its location:

```bash
node tools/testing/run-host-tests.mjs /path/to/godot
node --test tests/workspace-paths.test.mjs tests/model-capabilities.test.mjs
node tools/testing/run-pi-e2e.mjs /path/to/godot /path/to/pi
```

The reliability suite covers fallback snapshot preservation across reopening, startup failure rollback, changed dependencies (including preload), rename rebinding, immediate retry after Stop, cancelled compaction, atomic JSON replacement, and settings write failures. Node tests cover workspace roots, symlink/junction escapes, Git aliases, and exact versus unknown model capabilities. Pi acceptance also verifies a stalled provider connection is closed by Stop, immediate resume, and conversation preservation after rename.

The workflow performs, in order:

1. deterministic verification of the root Windows folder;
2. `tools/windows-bootstrap` Go unit tests when Go is available;
3. the fast headless Godot host/core/UI suite;
4. the real-window hostile generated-input regression under `xvfb-run` when available;
5. one real globally installed Pi run covering Parts 1–4: normal-agent behavior, native compaction, migration/runtime removal, and packaging/discovery;
6. a process-level migration check from the old `GameSmith Host` writable directory to `GameSmithHost`.

## Real Pi acceptance

`run-pi-e2e.sh` starts `../fake-openai-endpoint/pi-server.mjs` and drives the actual globally installed `pi` executable over GameSmith's production JSONL RPC path. The deterministic server speaks streaming OpenAI-compatible `/v1/chat/completions` and requires only Node's standard library.

CI pins `@earendil-works/pi-coding-agent@0.99.2`. For local runs you may point GameSmith at another explicit Pi executable with `GAMESMITH_PI_BIN`.

The release gate runs the Pi suite once with no phase selector:

```bash
GODOT_BIN=/path/to/godot tools/testing/run-pi-e2e.sh
```

For focused development, `GAMESMITH_PI_TEST_PART=1`, `2`, `3`, or `4` still runs only that slice.

Part 1 covers production controller selection, missing-Pi diagnostics, generation/edit/reload/Git behavior, streaming assistant/thinking events, false-completion recovery, native retry behavior, action limits, provider-call pacing, Pi session restart/resume, hidden diagnostic notices, and filtered runtime-log reads through real Pi.

`diagnostics_runner.gd` checks persistent startup/live capture, timestamps and attempt identities, unchanged startup rejection, session lifecycle, filtering and notification suppression, raw pagination, queue overflow, segment/session retention, write failures, interrupted JSONL tails, Windows rename, and snapshot fallback. The portable host runner and full verification workflow include this suite.

Part 2 covers manual and threshold-triggered Pi-native compaction, `keepRecentTokens`, persisted native compaction entries, checkpoint delivery to the next provider request, normal no-op classification, and byte-stable session entries across GameSmith restart.

Part 3 seeds a pre-Pi readable transcript and proves that it is imported into an empty Pi session exactly once, that the current request is not duplicated into the imported legacy block, that restart does not re-import it, and that production no longer contains the deleted homegrown agent/provider/compaction sources.

Part 4 verifies the explicit `GAMESMITH_PI_BIN` path, automatic discovery of a globally npm-installed `pi` from `PATH`, Windows README install guidance, and launcher-level Pi preflight behavior.

The production default Pi turn limit is 150. Runaway fixtures use a deliberately small test limit so acceptance does not waste provider round trips proving the same host-policy branch.

## Expected parse errors

Some host/runtime tests deliberately write invalid generated GDScript. Godot will print parse errors for those candidates. The tests only pass when GameSmith rejects the bad candidate, preserves or recovers the previous working game, and continues correctly.
