# Native image generation

Select a backend in **Settings > Images**, then save. **Check installed backends** checks CLI availability and existing native sign-in without generating an image. No backend is selected by default. Generation uses exactly the selected backend and its existing authentication; it never falls back to another vendor or a direct image API.

The game agent can call:

```json
{
  "action": "start",
  "prompt": "A friendly forest creature icon",
  "target_path": "assets/generated/forest-creature.png",
  "reference_paths": ["assets/reference.png"],
  "purpose": "inventory icon",
  "transparent": true
}
```

`prompt` is required for start. Other fields are optional; the default destination is `assets/generated/image.png`. Paths must be relative to the current game. Up to four PNG/JPEG/WebP references are copied into the private job directory. Poll `action=status` with the returned `job_id` until `state=completed` or `failed`. `action=stop` cancels the job; `action=capabilities` reports checked candidates and the selected backend. A completed result includes `path`, `width`, `height`, `format` and `harness`.

Keep game files unchanged while the job runs. GameSmith compares file hashes before publishing and rejects concurrent edits instead of overwriting them. The worker receives the image prompt, purpose, private copies of references and a private output location, rather than the game directory or main coding conversation. Native tools are restricted to image generation. These native permission policies are not an operating-system sandbox. Credential files are never copied into the game.

GameSmith checks destination ancestors for symlink/junction escapes, decodes the result with Godot, checks dimensions and requested transparency, and publishes a PNG to the requested path. Native URLs or success prose alone are insufficient. Publication replaces an existing image at that exact destination. Invalid results and jobs cancelled before publication are not published; Stop does not undo an already committed image. Jobs allow images up to 32 MiB and 64 megapixels, with neither dimension above 16384. File-change verification currently limits workspaces to 50,000 entries, excluding `.git` and `.godot` contents.

## Native routes

| Backend | Route | Current installed-account evidence |
| --- | --- | --- |
| Antigravity / AGY | Isolated custom agent, requesting the built-in `image-generator` subagent; only image generation/delegation is admitted | Native image tool detected; final live attempt blocked by unsupported user location |
| Codex | Ephemeral app-server thread with subscription-backed native `imageGeneration` result | Real generation and reference-image generation both decoded and published successfully |
| Grok Build | Separate ACP session using `image_gen` / `image_edit`, the native Imagine tools | Final live attempt reached `image_gen`, then returned HTTP 403 spending-limit/subscription error |
| Cursor | Native print mode, reading structured `generateImageToolCall` results | Final authenticated live attempt blocked by account usage limit |

Cursor's installed ACP implementation asks the client to perform `cursor/generate_image`; it does not supply a generated artifact. The print route uses Cursor's own generator instead. AGY, Grok and Cursor successful artifact discovery and reference handling have deterministic fixture coverage, but their current account restrictions prevented successful live image/reference acceptance. They should not be described as verified end to end. Reference paths are passed to native image tools; whether a model faithfully follows a reference remains a visual check.

AGY subagent IDs come from its documented [`subagent_info` stream records](https://antigravity.google/docs/cli/headless/). Its native generator writes to [conversation-specific artifact directories](https://github.com/google-antigravity/antigravity-sdk-python/blob/main/examples/deep_dives/multimodal_pipeline.py). GameSmith accepts structured artifact paths or one image in this fresh job's conversation directories. It never searches other conversations and rejects ambiguous results, references passed back as output, and foreign artifact paths.

Capability probes cannot guarantee image entitlement, regional availability or remaining quota without an actual image turn. Native generation failures are retained outside the game and shown alongside later capability checks. Resolve the reported problem and explicitly retry the selected backend. No vendor switch happens automatically. A five-minute deadline and the existing GameSmith process-tree cancellation path bound native jobs.

Older Codex coding conversations have a fixed tool registry. If they predate `generate_image`, use **Settings > This game > Start new Codex session** to obtain the new tool. This explicitly starts fresh native context and preserves the displayed chat; image settings never silently archive a conversation.

## Verification

`node tools/testing/verify.mjs --test node:image-generation,host:image_generation --output summary` runs the assembled native adapters against deterministic fixtures. The live runner is deliberately excluded from normal suites because it consumes account allowance:

```powershell
$env:GAMESMITH_IMAGE_LIVE_BACKEND = 'codex'
$env:GAMESMITH_CODEX_BIN = 'C:/GameInGame/tools/testing/codex-luna-launcher.mjs'
node tools/testing/verify.mjs --test host:image_generation_live --output errors
```

Live Codex acceptance explicitly uses `gpt-6-luna` with `xhigh` reasoning. Set `GAMESMITH_IMAGE_LIVE_REFERENCE` to an existing image to test references; the runner copies it into the isolated game. For live Cursor on Windows, preserve native credential access while isolating Godot data using the existing test wrapper:

```powershell
$env:GAMESMITH_IMAGE_LIVE_BACKEND = 'cursor'
$env:GAMESMITH_CURSOR_BIN = 'C:/GameInGame/tools/testing/live-cursor.mjs'
$env:GAMESMITH_TEST_NATIVE_APPDATA = $env:APPDATA
node tools/testing/verify.mjs --test host:image_generation_live --output errors
```
