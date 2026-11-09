# Native customization probes: Grok Build and Cursor

Scope: investigate personal hook/MCP startup through installed native CLIs and
assembled GameSmith server modules. Preserve native authentication/model behavior,
managed policy and GameSmith image guards. Do not modify real user configuration.
A missing positive control is inconclusive, not evidence of isolation.

- [x] Inspect installed versions, customization controls and existing adapters.
- [x] Add isolated-profile native positive controls and assembled-server probes.
- [x] Record demonstrated leakage, startup blockers and unproven claims separately.
- [x] Correct the documentation's tool-policy/startup-code distinction.
- [ ] Fix Grok auth-method compatibility with focused protocol/lifecycle coverage.
- [ ] Find and prove a supported native customization suppression mode before
  changing launch behavior. Retain GameSmith image guards and native login.
- [ ] After a production fix, verify full registry, fresh/resumed sessions, Stop,
  model/auth parity and packaged behavior. These are not claimed by this probe.
- [x] Commit and push the completed audit.

## Reproduction and results

Run `node tools/testing/probe-native-customization.mjs` on Windows with both CLIs
installed. The script runs the production runtime assembly path, then imports
those server modules. Native controls use the same native-tool restrictions.
Each case gets its own temporary HOME/USERPROFILE/APPDATA/config, synthetic
credentials and harmless hook/MCP files. A localhost metadata stub serves Cursor;
it does not supply inference responses. No personal credentials are copied.
Each case is bounded to 20 seconds and owned process trees are stopped afterward.

Completed on 2026-11-09 against source `d77aa09`:

| Installed binary | Case | Personal hook ran | Personal MCP started | Explicit probe MCP started |
| --- | --- | --- | --- | --- |
| Grok 1.0.70 (f50904eaee6c) | Native ACP control | Yes | Yes | Not supplied |
| Grok 1.0.70 (f50904eaee6c) | Assembled server | No; initialization rejected | No | No |
| Cursor 2026.10.22-27dcf5f | Native ACP control | Not observed | Yes | Not supplied |
| Cursor 2026.10.22-27dcf5f | Assembled ACP server | Not observed | Yes | Yes |
| Cursor 2026.10.22-27dcf5f | Assembled image launch | Yes | Yes | Not supplied |

Evidence: `%TEMP%/gs-native-customization-fSGK6I/results.json`, per-case
`probe.stdout`, `probe.stderr`, native diagnostics and marker files. Personal hook
configuration bytes were checked unchanged. The explicit probe MCP is a tiny
startup marker server, not the complete GameSmith tool registry. The image case
stops after observing hooks; no generated image or successful inference is claimed.

The first run (`%TEMP%/gs-native-customization-zPWCnQ`) stopped at Grok's adapter
startup rejection. The revised reproducer records that rejection as a finding and
continues; it does not turn it into an adapter acceptance pass.

## Conclusions and bounded follow-ups

1. **Cursor startup executes personal code.** Denying external MCP tool invocation
   does not stop the MCP process from starting. The image-launch personal hook
   also runs outside model tool permissions. This is inherited trusted-user
   configuration, not a demonstrated untrusted-game escape.
2. **Grok native control executes personal code, but its adapter is blocked.**
   The installed CLI advertises `xai.api_key`/`grok.com`; GameSmith's server requires
   `cached_token`. It reports a misleading wrong-executable error before session
   creation. Do not claim an assembled-adapter hook reproduction for this version.
3. **Prompt/rule inheritance remains unproven.** Cursor's metadata stub does not
   provide a usable inference stream. No conclusions about actual inference,
   custom-agent instructions, native selected models, subscription login, session
   resume or provider-side Stop behavior can be drawn from these results.

No production flags were changed. Relocating native homes could also relocate
authentication or managed configuration. Disabling all project hooks could remove
GameSmith's image policy guard. Neither is an acceptable untested shortcut.
No new sandbox, config sanitizer or cross-harness policy framework was introduced.

Do not expand the audit to CodeBuddy/Cline until these findings have a concrete
resolution or an explicitly accepted limitation. The reproducible observations
are more useful than another speculative inventory of possible customizations.

## Verification

- Installed-CLI reproducer completed all five cases, including recorded Grok
  initialization failure; no successful Grok adapter acceptance is claimed.
- Final reproducer run with the completed assertions:
  `%TEMP%/gs-native-customization-XSID43`; same five observations, exit zero.
- `node --check tools/testing/probe-native-customization.mjs`, `git diff --check`
  and the three added relative documentation links pass.
- `node --test tests/pi-pin.test.mjs`: 2/2 passed.
- No production runtime files changed; no PCK rebuild or full deterministic suite
  is required for this audit. No GitHub CI or paid-provider acceptance was run.
