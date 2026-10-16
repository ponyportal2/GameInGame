# Persistent Command-code ACP

- [x] Validate candidate 1.82.1 with the existing transport and inspect native ACP/mod behavior.
- [x] Add failing tests for persistent sessions, policy readiness, lifecycle and compaction.
- [x] Implement persistent ACP with the existing private mod and launch/session readiness checks.
- [x] Verify actual provider tool/prompt boundaries and deliberate policy failures.
- [x] Run host lifecycle and live acceptance, rebuild Windows package, document results and limits.

Keep model/provider/reasoning native-owned. Keep existing game tools and workspace guard in the mod. No GitHub CI runs.

## Evidence and accepted limits

- Old transport + isolated candidate 1.82.1: real selected-model acceptance passed 6 checks (`gamesmith-tests-VBhBLf`).
- Final Node suite: 168 passed, 0 failed, with native provider-boundary test enabled (`%TEMP%/gs-acp-node-final.log`). A subsequent added forbidden-call regression passed 36 captured provider requests (`%TEMP%/gs-acp-boundary-final.log`).
- Persistent ACP real free-model acceptance: 14 checks passed, including streaming, backend reuse, reopen/history, a 65-second reload approval wait, actual reload and Stop/resume (`gamesmith-tests-nGBcZd`, `%TEMP%/gs-command-live-acp.log`).
- Exported PCK: adapter contents, Command-code lifecycle (16 checks) and compaction (10 checks) passed in an isolated directory (`gs-acp-pack-_4tww05l`). The deliberate broken-game parse error is expected reload-repair coverage.
- Uninterrupted complete host suite: all 31 runners passed with exit 0 (`gamesmith-tests-vs3W45`, `%TEMP%/gs-acp-host-all.log`). No split-run success claim or CI run.
- Native ACP ignores root `--mod`; an inert supported user-mod loader activates only for nonce-marked GameSmith launches. Initialization and exact session allowlist are verified independently before inference.
- Native 1.82.1 injects tool discovery outside the mod registry. Disabled deny-only registrations prevent those schemas from being injected; actual provider requests prove the exact 18-tool set.
- Native uncaught ModApi guard exceptions allow execution. The whole GameSmith guard now catches failures and explicitly denies; injected validator failure prevented a write.
- Native 1.82.1 still advertises disabled tools in an unfiltered system-prompt catalog. The user explicitly accepted shipping with this documented limitation. Exact callable schemas contain only the 18 allowed tools; a hallucinated shell call was rejected. No claim of an entirely clean model-visible prompt.
- An intermediate extended host test exposed missing `last_error` propagation; fixed and verified in the packaged lifecycle test. An initial forbidden-call assertion missed native wording “No tool named”; corrected the assertion, without changing product behavior.
- Native history is workspace-bound. Session reset archives its reference, enabling rename before a fresh session is created. Missing saved IDs fail before inference and offer reset instead of silently starting empty history.
- Installed CLI upgraded to 1.82.1; selected native model remains `stealth/glyph-cluster:free`. Provider credentials/settings were not rewritten. Windows PCK rebuilt and self-contained package verification passed.
- Exported PCK + globally installed npm launcher + selected free model: all 14 real acceptance checks passed with exit 0 (`gs-acp-pack-live-oluvm0fz`, `%TEMP%/gs-acp-pack-live.log`). This includes editing, headless testing, streaming, process reuse, reopen/history, 65-second approval, actual reload and Stop/resume.
- Final uninterrupted Node run used the globally installed CLI: 168 passed, 0 failed, including all 36 provider-boundary requests (`%TEMP%/gs-acp-node-final.log`).
