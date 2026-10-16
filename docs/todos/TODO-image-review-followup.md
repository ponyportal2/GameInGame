# Native image review follow-up

- [x] Validate Grok's returned artifact under configured home and exact session, treating cwd groups as opaque.
- [x] Cover custom home, long cwd grouping, foreign session and link escapes with assembled native fixtures.
- [x] Clean private image job directories after process shutdown; verify completion, failure, cancellation and probe cleanup.
- [x] Run focused consumer/package checks and rebuild Windows package; prepare intended files for commit and push.

No new storage discovery algorithm, vendor fallback or retention subsystem. Native harness caches remain owned by their harnesses. Live Grok output remains unverified because the existing account test hit a spending/subscription restriction.

Verification: `%TEMP%/gamesmith-image-review-fix/results.json` passed 7/7 steps, 97 assertions, zero failures/skips. Includes all four assembled image routes, custom/default Grok storage and hashed long-cwd fixtures, foreign-session/link rejection, host cleanup and preserved game files, runtime assembly and rebuilt-package checks. No provider calls or GitHub CI. Cleanup reuses the existing link-aware deletion helper; failures retain private data and log a warning, with no legacy-directory sweep.
