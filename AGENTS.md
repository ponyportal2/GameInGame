# GameSmith project guidance

Last updated: 2026-10-16 18:00 (Asia/Novosibirsk, UTC+07:00).

## Working conventions

- Keep task checklists and verification evidence in `docs/todos/`, not the repository root. Maintain a short checklist for substantial work.
- Preserve unrelated user files, screenshots, archives, and local changes. Stage only intended changes.
- Prefer `rg` and `fd` for searches, `eza` for directory listings, `jq` for JSON, and PowerShell shorthands where available.

## Verification without unnecessary overhead

- Use `node tools/testing/verify.mjs --suite affected --since main --output summary` for focused changes; the `--since` ref keeps committed branch work in the selection. Choose broader suites when shared behavior or release scope warrants them. See `tools/testing/README.md` for commands and contracts.
- Output modes change presentation, not test coverage or saved evidence. Prefer `summary` or `errors`; use `full` when investigating a failure.
- Let the runner report phases, failures, stalls, and completion. Do not repeatedly poll `progress.json` or narrate counters. Inspect progress only for an apparent stall; read `results.json` at completion and open individual logs only when needed.
- Trust structured results and exit status, not searches for the word `ERROR`; some tests deliberately produce diagnostics.
- Rerun failed tests with `--rerun-failed <results.json>`. Do not repeat passing suites without new changes or unresolved concerns. Reuse evidence only through the runner's fingerprint checks.
- Keep Godot runners isolated. Avoid editing tested inputs during a run. Documentation-only changes need link/diff checks rather than a full suite or executable rebuild.

## Native harnesses and live tests

- For every live Codex test, explicitly select `gpt-6-luna` with `xhigh` reasoning through flags. Use `tools/testing/codex-luna-launcher.mjs` via `GAMESMITH_CODEX_BIN`; do not rely on the user's default model or alter global Codex settings.
- Model overrides for testing must not leak into GameSmith's production harness settings. Respect each harness's native settings contract.
- Prefer deterministic fixtures for development; live acceptance consumes provider allowance. Report fixture, real-provider, source, and packaged results separately, including failures and limitations.
- Do not dispatch GitHub CI unless requested. When pushing a Windows runtime change, rebuild the package unless the user says otherwise; verify the pushed remote revision.

## Shared implementation

- Use `tools/agent/harnesses.json` and the existing runtime assembly path for harness metadata/module wiring. Tests should execute the same assembled modules shipped by production.
- Changes to shared modules require coverage for their consumers, not just the directory that owns the source.
- Extract small, genuinely shared utilities; preserve harness-specific session, cancellation, permission, and protocol semantics. Avoid a generic framework full of behavioral switches.
- Keep native session identity and recovery explicit. Never silently discard history or weaken tool/workspace restrictions to make an integration pass.
