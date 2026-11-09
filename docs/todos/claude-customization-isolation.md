# Claude customization isolation

- [x] Probe the installed CLI with isolated profiles and a local deterministic provider: ordinary positive controls, safe mode, then restricted mode if needed.
- [x] Select only a proven minimal launch change that preserves explicit GameSmith MCP, instructions, native model/configuration and session lifecycle.
- [x] Add the regression before the production change; retain explicit tool restrictions and managed policy.
- [x] Run focused deterministic, installed-CLI and packaged checks; record authentication limitations separately.
- [x] Rebuild the Windows runtime and prepare the tested delivery commit. Remote revision confirmation is reported after pushing.

No user/global Claude configuration is changed. Bare mode is not a production candidate because it omits subscription OAuth/keychain authentication.

## Installed CLI experiments

Claude Code 2.1.317, real executable, isolated native profile and deterministic localhost provider. Corrected probe artifacts: `%TEMP%/gs-claude-isolation-BTdk8F` (`results.json`, request bodies and per-mode native output). An earlier probe checked only system blocks for `CLAUDE.md`; the corrected probe checks the complete request because native memory arrives in a user-message system reminder.

| Launch | GameSmith tools | User agent / CLAUDE.md | Native model |
| --- | --- | --- | --- |
| Ordinary positive control | All 25 | Loaded when configured | Preserved |
| `--safe-mode` | None | Suppressed | Preserved |
| `--restricted` | All 25 | Suppressed | Changed to default instead of selected model |
| Explicit `agent: ""` and `env.CLAUDE_CODE_DISABLE_CLAUDE_MDS: "1"` | All 25 | Suppressed | Preserved |

Use only the two targeted settings overrides, alongside the existing hook/memory restrictions. Authentication/model configuration remains native; managed settings retain their normal precedence. No settings parser, private credential copy or broad isolation mode was added.

## Regression evidence

- Before production changes, `node --test tests/claude.test.mjs` failed on the absent agent override; installed-CLI acceptance failed because the global custom-agent sentinel reached inference.
- After the two overrides, the launch regression passed and installed-CLI acceptance passed: `%TEMP%/gs-claude-isolation-AsiZhR`. Both native customization positive controls passed, followed by isolated fresh/resumed/after-Stop requests, system instructions, model selection, exact MCP execution and API-key/OAuth fixture discovery.
- The synthetic OAuth credential tests the native credential read path only. It does not prove a valid Anthropic subscription. Real-provider results are recorded separately below.

## Final verification

- Focused deterministic/source/package selection: **9 selected / 11 entries passed, 795 assertions, zero failures, skips or reused entries**, 192.7 seconds. `%TEMP%/gamesmith-verify-9TkmFl/results.json`. Selected the complete Claude suite plus package contents/structure explicitly; the optional installed-CLI experiment is run separately. No shared implementation changed, so no exhaustive rerun was needed.
- Rebuilt-PCK Claude lifecycle: **52/52 passed, exit 0**. `%TEMP%/gamesmith-claude-isolation-package-pfCbP5/results.json`. External copy of the production lifecycle runner, with only the unbundled fake-CLI fixture path redirected into the isolated temporary directory. Tested PCK SHA-256: `d0fdb3731e4808566900bdf35bd5814c7bc4013e687c1032006680ebee1a4188`.
- Real-provider assembled worker: `node tools/testing/verify-claude.mjs` **passed** with installed Claude Code 2.1.317 and the unchanged native model **deepseek/deepseek-v4.1-flash-1017**. Actual file write, guarded outside-read attempt, same-backend history, explicit session resume, Stop and continuation; `%TEMP%/gamesmith-claude-live-9AFWud`. This is native-provider acceptance, not an Anthropic subscription inference test.
- Documentation pin regressions: `node --test tests/pi-pin.test.mjs`, **2/2 passed**. Diff whitespace checks passed. Launcher unchanged; no CI was dispatched.
