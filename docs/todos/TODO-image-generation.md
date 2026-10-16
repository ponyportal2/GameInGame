# Image generation through native harnesses

- [x] Inspect existing lifecycle/assembly, installed CLI image mechanisms and capability detection.
- [x] Implement a small isolated job path for AGY, Codex, Grok Build and Cursor; fail explicitly for unsupported capabilities.
- [x] Expose generate_image and backend settings with workspace image validation and cancellation.
- [x] Test deterministic contracts and real installed harnesses, keeping failures/limitations explicit.
- [x] Rebuild/check Windows package and prepare intended files for commit and push.

No direct image-provider APIs, credential copies, vendor fallback or new general-purpose process supervisor.

## Decisions

Reuse canonical harness assembly, native server classes and CommandCodeSession/PiRpcSession process ownership. Settings choose one image backend globally, initially disabled. Image jobs use disposable native workspaces, native tool restrictions, validated reference copies and bounded metadata. Godot decodes the result before publication; game file hashes and path checks prevent publishing over concurrent edits or through escaping links. Native restrictions are not an OS sandbox.

AGY prefers its built-in image-generator subagent and accepts artifacts only from this job's private workspace or its fresh conversation IDs. Grok uses native image_gen/image_edit. Cursor's installed ACP requests client-side generation, so its own structured print-mode image tool is used instead. Codex uses an ephemeral subscription-backed native image thread. Older coding threads need the existing explicit Start new Codex session action to discover the new tool; no history is silently discarded.

## Local verification

Evidence directories below are under `%TEMP%`.

- `gamesmith-images-affected/results.json`: rebuilt package and full conservative affected selection, 78/80 steps passed; only failures were stale OpenCode/OMP tool counts. 2214 passing assertions, two failures and one existing skip. No inputs changed during this run.
- `gamesmith-images-consumer-rerun/results.json`: failure-only rerun passed 3/3 steps after updating both counts and asserting the new tool is advertised.
- Earlier focused development caught a nonexistent JsonStore helper, a corrupt PNG fixture, and an incorrect Godot grandchild-liveness assertion. These were corrected; `gamesmith-images-focused-5/results.json` passed the failure-only image-host rerun.
- `gamesmith-images-final/results.json`: final focused adapter, image host, settings, minimum-window layout, assembly and rebuilt-package checks passed 9/9 steps, 210 assertions, zero failures/skips. Includes 26/26 Node image tests, all four native cancellation fixtures, AGY owned-artifact/ambiguity checks, and capability recovery after a successful retry.

## Real installed harnesses

- Codex: `gamesmith-image-live-codex-final/results.json` and `gamesmith-image-live-codex-reference/results.json` both passed (2/2 steps each). Actual 1254x1254 PNGs decoded and published; unrelated game file remained unchanged. Visual inspection confirmed the reference edit changed the blue circle to green while preserving composition. Explicit gpt-6-luna/xhigh through codex-luna-launcher.mjs, without production model changes.
- AGY: `gamesmith-image-live-agy-final`: FAILED_PRECONDITION, user location not supported. Tool advertised, but no successful image/reference acceptance possible.
- Grok Build: `gamesmith-image-live-grok-final-2`: native image_gen reached, then HTTP 403 personal-team spending-limit/subscription restriction. Initial attempt exposed an overly broad Edit deny (also covers ImageGen); image-only hooks now deny ordinary edits without blocking native ImageGen.
- Cursor: `gamesmith-image-live-cursor-final-auth`: authenticated CLI returned account usage limit. Earlier isolated-APPDATA attempt could not see native authentication; final attempt used the existing live-cursor wrapper, without copying credentials. Initial native output also exposed a Write permission issue, fixed with the exact private output allowance and a restrictive tool hook.

Only Codex has successful live end-to-end image/reference evidence. The other three routes have fixture coverage and explicit real-account blockers, not successful live acceptance. Live cancellation/reference fidelity for those accounts remains unverified. No GitHub CI dispatched.
