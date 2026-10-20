# Harness fixture drift: tool surface and non-ASCII assembly

Status: done (2026-10-20)

Two long-standing red tests were caused by the fixtures, not by product code.

## 1. Stale host-tool counts

`tests/opencode.test.mjs` asserted `tools/list` returned exactly 17 tools and
`tests/omp-server.test.mjs` asserted the OMP backend registered exactly 22. Both
numbers predate `delete_path` and `move_path`, so the suites failed with
`19 !== 17` and `24 !== 22` while the product behaved correctly.

Both assertions now compare the sorted tool-name list instead of a magic count,
so an addition or removal names the offending tool in the diff:

- OpenCode: the 19 host tools from `tools/opencode/host-tools.mjs`.
- OMP: the 19 host tools plus the five native workspace tools
  (`read`, `write`, `edit`, `list`, `search`), all `gamesmith_`-prefixed.

## 2. Recursive copy silently skipped non-ASCII destinations

`tools/testing/assembled-runtime.mjs` copied the assembled runtime with
`cpSync(template, destination, {recursive:true})`. On this Node build (24.16.0,
Windows) that call copies **nothing** when the destination path contains
non-ASCII characters, and reports no error. The Grok `grok-long` fixture
deliberately uses a 35-`é` directory, so the child failed with
`Cannot find module ...\private-ééé…\image-worker.mjs`.

Reproduced in isolation: `cpSync` into `private-ééééé` copies zero entries,
while `writeFileSync`/`copyFileSync` in the same directory work, and an
ASCII-named destination of the same length copies correctly.

`assembleHarnessRuntime` now verifies that every top-level entry landed and, if
not, walks the tree explicitly with `mkdirSync` + `copyFileSync`. The fixture
keeps its non-ASCII path coverage instead of dropping the case.

## Evidence

```
node --test --test-reporter=tap tests/opencode.test.mjs     # pass 4  fail 0
node --test --test-reporter=tap tests/omp-server.test.mjs   # pass 10 fail 0
node --test --test-reporter=tap tests/image-generation.test.mjs  # pass 32 fail 0
node tools/testing/verify.mjs --suite full --output summary --build-package
PASSED: {"passed":89,"failed":0,"blocked":0,"interrupted":0,"reused":0,"skipped":0}; 2185.4s
```

Before: 5 tests failed (opencode, omp-server, image-generation,
review_stop, kilo_stop).
