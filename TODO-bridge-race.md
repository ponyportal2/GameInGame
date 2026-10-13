# Windows host-bridge race investigation

Branch: `fix/windows-bridge-claim-20261013`
Base: `ca850efbf734029213996320f5c7221ae6f9bbfd`

## Evidence preserved before the fix

- Original follow-up full host run failed at Cline's first manual reload after the preceding 19 runners passed; isolated Cline then passed.
- A fresh Windows Actions full-suite reproduction (`38404456624`) instead passed Cline completely and failed Cursor at the same first manual reload boundary. Cursor inherits the Cline reload-grant bridge path.
- Cline Node protocol/worker tests passed 20 consecutive iterations in `38405539340`.
- Fresh isolated Cline lifecycle runs in that same job passed 8 consecutive times, then iteration 9 failed exactly at the first reload reaching approval/completing. Later checks in the same lifecycle passed. This rules out prior host-run global settings as the required cause.
- Deterministic Windows lock regression `38406435696` holds a real `request-*.json` open with read/write sharing but without delete sharing. Current GameSmith reads and acts on the request even though `DirAccess.remove_absolute()` cannot claim/remove it. For Cline, the still-live special request can then fall through to the superclass bridge pass and receive a second/conflicting response.

## Working root cause

Host bridge consumers execute request contents before proving exclusive ownership of the request file. On Windows a producer can leave the request readable while temporarily denying delete/rename. The base Pi bridge and Cline's special `authorize_reload` / grant-backed `reload_game` bridge both ignore removal failure. Cline then scans the same live request again through `super._service_host_bridge()`.

The fix should atomically claim each live request out of the `request-*.json` namespace before dispatch, then dispatch it exactly once. Cline-specific commands should override dispatch rather than perform an independent pre-scan.

## Checklist

- [x] Preserve previous full-suite and isolated reproduction evidence.
- [x] Reproduce the race deterministically with a Windows file lock.
- [ ] Add the deterministic bridge-claim regression to this branch.
- [ ] Refactor base host bridge to claim before dispatch.
- [ ] Route Cline/Cursor special bridge commands through the same claimed-request dispatcher.
- [ ] Run focused Windows bridge regression.
- [ ] Add a short repeated Cline/Cursor initial-reload smoke (avoid long lifecycle loops).
- [ ] Run focused Cline/Cursor Node tests.
- [ ] Inspect/use the repo's v1/fake endpoint emulator where useful.
- [ ] Run bounded representative host tests and one clean full host suite asynchronously if focused tests are green.
- [ ] Update this TODO with exact evidence before merge.
- [ ] Merge only after the regression is green and no new cross-harness failure appears.
