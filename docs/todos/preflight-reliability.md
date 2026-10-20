# Preflight reliability

- [x] Make the serialized-resource regression fail with diagnostics rather than hanging. Its full source run passed (104 assertions); the historical startup stall did not reproduce.
- [x] Reproduce and fix the independent final-status read/exit race. The controlled real-PID regression failed two assertions before the fix and passed afterward, including the missing-evidence case.
- [x] Verify affected source behavior and rebuilt package; record limitations.
- [x] Prepare the intended changes for commit/push (remote verification reported in the final response).

The shutdown race can explain an unconfirmed clean exit, but does not explain
every previously observed startup stall. No timeout or smoke requirement changed.

Verification:

- Red: `gamesmith-verify-yhgvTC` reproduced two final-status assertions failing.
- Green: `gamesmith-verify-Q5Yjgw` passed the new exit regression.
- Final: `%TEMP%/gamesmith-verify-3LMVWq/results.json`, 9/9 entries passed,
  265 assertions, 293.7 seconds, no failures, skips or reused evidence.
  Selection: verification-runner contracts, exit-race regression, detached
  process suite (95 assertions), reload preflight (40), runtime children (104),
  package build, package contents and package structure.
- No real-provider calls or visual gameplay checks. The serialized-resource
  regression passed twice; the historical startup stall remains unreproduced.
