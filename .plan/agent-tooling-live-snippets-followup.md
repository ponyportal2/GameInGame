# TODO — agent tools + live snippets follow-up

Evidence: uploaded production conversation showed `read_file` returning a 30 KB preview and `patch_file` accidentally reusing that preview as the source of truth, which truncated a ~46 KB `main.gd`. The same session then forced the model to rewrite the entire file. Live snippets also currently feed raw text into a BBCode parser.

Research basis:
- Pi coding agent: bounded/offset reads; exact unique edit matches; editing is separate from read-preview truncation.
- OMP/Oh My Pi: read ranges + snapshot/anchor-aware edits; fail-safe validation rather than applying edits against elided content.
- GameSmith stays narrower: no shell, no hashline grammar yet (YAGNI).

## TDD
- [x] RED: regression for patching a file larger than the old 30 KB preview cap.
- [x] RED: regression for ranged/continuable reads with explicit truncation metadata.
- [x] RED: reasoning fallback when `reasoning_content` is null but a string `reasoning` field exists.
- [x] RED: literal BBCode in user/agent/tool text must render literally.
- [ ] GREEN: make `patch_file` operate on the complete file, never a display preview.
- [ ] GREEN: make `read_file` line-windowed (`offset`/`limit`) with continuation metadata.
- [ ] GREEN: expose the safer read contract in the model-facing tool schema/system guidance.
- [ ] GREEN: keep THINK snippets, but only from explicit string reasoning fields; ignore structured/unknown reasoning payloads.
- [ ] GREEN: escape BBCode for all untrusted chat text while retaining host role styling.
- [ ] REFACTOR: rename docs/concepts from “streaming” to “live/intermediate snippets” where practical.
- [ ] VERIFY: full source, windowed, fake-v1 HTTP, restart, Windows folder build.
