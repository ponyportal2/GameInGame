# Harness switching

- [x] Add failing regression tests for saved switches, cancellation, busy protection, and preservation.
- [x] Add per-game harness settings and safe controller replacement.
- [x] Run host tests and rebuild/verify Windows package.
- [x] Document behavior, commit and push.

Regression first failed because existing-game harness selection was absent. Focused suite now passes switches among all three controllers, cancellation, busy rejection, backend retirement, saved reopen, and file/transcript/session preservation. Windows PCK export, contents, and self-contained package checks passed.

Full isolated host suite passed (exit 0), including both native adapter lifecycle fixtures and process-tree shutdown. User screenshots excluded from commit and package.
