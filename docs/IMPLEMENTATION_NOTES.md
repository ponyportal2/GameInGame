# Implementation notes

## Spike results

- Runtime GDScript compilation: passed with `GDScript.new()`, `source_code`, `reload()`.
- Runtime sibling script loading: passed from `user://` game workspaces.
- Pause/chat: host UI uses `PROCESS_MODE_ALWAYS`; generated games inherit pausable behavior.
- Runtime logs: host keeps a bounded structured load log and exposes the tail of Godot's file log as a fallback.

## Deliberate v1 limits

- No screenshot or autonomous gameplay tool for the LLM.
- No `.tscn` generation, binary assets, state-preserving reload, static preflight pipeline, or automatic repair loop.
- Same-process generated GDScript remains a weak security boundary, matching the spec's v1 tradeoff.
- OpenAI subscription OAuth/Codex CLI integration is left as an adapter seam instead of emulating unsupported credentials.
- Command Code's OpenAI-compatible endpoint is used; select a non-Claude model in this build.

## Agent integration test seam

`AgentController.provider_override` is a narrow dependency-injection seam used by deterministic tests. Production leaves it `null`, so normal provider selection still goes through `ProviderFactory`. This avoids introducing a separate fake agent stack: simulated model responses still drive the real structured tools, Git service, runtime loader, and transcript persistence.
