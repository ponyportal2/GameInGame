# Bounded detached runtime search

- [x] Regress permanently pending detached inspection through assembled tools.
- [x] Return pending inspection unchanged; preserve cancellation and completed-page rg filtering.
- [x] Explain that polling returns the inspection page, without automatic regex continuation.
- [x] Verify shared consumers and rebuilt Windows package.
- [x] Prepare commit and push delivery.

Scope: remove internal polling only. Reuse existing test action/poll controls;
do not introduce search jobs, deadlines, or another async protocol.

TDD: the new permanently-pending fixture failed against the old loop at its
one-second safety deadline (AbortError). It uses assembled OpenCode production
modules; the fixture never completes inspection. Additional consumer coverage
checks the same pending behavior in all 15 shipped harness assemblies.

Validation selection: output/search regressions, all assembled runtime tool
consumers, canonical host assembly, and rebuilt package structure/contents.
The changed leaf module has no controller/lifecycle changes; another exhaustive
native lifecycle run is unnecessary for this bounded return-path fix.

Final verification (2026-11-09):

```powershell
node tools/testing/verify.mjs --test node:tool-output,node:runtime-properties,host:harness_assembly,package:contents,package:structure --output summary
```

- Results: `%TEMP%\gamesmith-verify-UPikQh\results.json`.
- 5 selected tests / 7 entries, all passed; 62 assertions, no failures,
  skips, or reused evidence; 137.3 seconds.
- All 15 assembled harness consumers exercise pending-result propagation.
  Completed detached pages still filter through actual system rg and retain
  original identities, scope, and pagination; cancellation and lifecycle errors
  remain covered.
- Rebuilt tracked Windows PCK; package contents and structure both passed.
- No real-provider calls or GitHub CI dispatch. The hung-getter boundary is a
  deterministic permanently-pending bridge fixture, not a deliberately wedged
  external Godot process.
- `git diff --check` passed.
