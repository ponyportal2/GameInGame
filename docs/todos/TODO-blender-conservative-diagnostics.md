# Conservative Blender diagnostic selection

- [x] Restrict selection to line-start warning/error labels and known built-in Python warning classes, each followed by a colon.
- [x] Remove generic diagnostic-word/phrase matching and cover ordinary text, embedded labels and arbitrary warning-class names with regressions.
- [x] Clarify that `warnings` contains selected diagnostic-looking lines; preserve the schema and bounded logs.
- [x] Run focused source, assembly and rebuilt Windows package checks.
- [x] Prepare the scoped commit for push; preserve the unrelated scratch archive.

No speculative exporter formats or filename/line-prefix parsing. This summary favors precision over completeness.

## Verification

- `%TEMP%/gamesmith-verify-L5Mm8Y/results.json`: all seven steps passed, with no failures, skips, blocked or interrupted steps. Node Blender 20/20; Blender host 130/130; runtime assembly 14/14; Windows package rebuilt; package contents and structure passed.
- Sources stayed unchanged during verification; this evidence annotation was added afterward. `git diff --check` passed.
- Deterministic source/assembly/package checks only. No live provider calls, new visual acceptance or GitHub CI.