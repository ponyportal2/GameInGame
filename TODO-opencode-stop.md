# OpenCode persistent backend and cancellation

- [x] Confirm orphaned installed processes in logs and add launcher/child shutdown coverage.
- [x] Add persistent HTTP/SSE server transport and native abort; reject overlapping requests.
- [x] Verify installed Chocolatey OpenCode Stop, same-session retry, backend reuse, and closing-process cleanup.
- [x] Finish host regressions, rebuild Windows package, document and push.

Evidence: 39 Node tests pass. Installed OpenCode acceptance passes native editing, headless testing, reopening history, and a 65-second reload approval. Native Stop acceptance passes all seven checks; deterministic lifecycle and shutdown checks pass. The Windows PCK was rebuilt and both bundled-content and self-contained-package checks pass. Initial full host run hit the existing test-process graceful-stop assertion; the isolated rerun passed 57/57 checks and all remaining host runners passed. Deliberate invalid-script reload cases print expected Godot parse errors.
