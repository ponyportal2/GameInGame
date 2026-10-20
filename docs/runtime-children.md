# Live additive children

`add_runtime_child(parent, candidate_path, name, script_path, properties?)` adds
one new scripted Node beneath a genuine live parent handle from `inspect_runtime`.
The script's `extends` determines its type. Constructors (including inherited
constructors) must accept no arguments. Scripts stay inside the game workspace
and obey the existing loading policy. Initial properties use the scalar/tagged
value types supported by `set_properties`: no object references or expressions.
Properties are set before insertion; the child can find its parent in `_ready()`.

Adding new code requires player consent through **Allow Child Code** (Shift+F5).
Settings > Agent & testing offers **Automatically approve live child additions**,
off by default and independent of reload and Blender approval. Approval uses the
current workspace files; cancellation discards the pending request. Approval is
consent to execute code inside GameSmith, not a sandbox or a safety guarantee.

The host starts its own isolated headless process, boots the current workspace,
waits for startup smoke, and inserts the child at the explicit game-relative
`candidate_path`. Parent engine class and script path must match the inspected
live target. Missing targets and duplicate child names reject, including when
persistent startup already creates the requested child. The injected copy must
survive at least four completed process and three physics ticks with the same
identity, parent and name, without being queued for deletion, and clean
shutdown. Cancellation, errors, hangs and changed code reject before live
application; the private preflight does not consume the agent's detached test.

After preflight, the host checks code/resource fingerprints and the live handle,
class/script and name collision again. Tree changes run outside the initiating
callback. A fresh component and its preload dependencies are compiled without
replacing scripts attached to existing objects. Workspace script, serialized
scene/resource and shader cache entries are temporarily detached so preloads
read current files; existing resource objects remain unchanged and injection
restores their cache entries afterward. Existing parent/sibling `_ready`
callbacks do not repeat. Late components do not automatically enter cached
parent registries or inherit new parent methods/signals from edited source.

Results distinguish `live_attempted=false` (no live insertion) from a live
attempt. Successful additions return the actual `handle`, `temporary=true` and
bounded preflight evidence. Failed live initialization removes the new child
where possible and returns `live_game_modified=null`: arbitrary constructor,
setter and initialization side effects cannot be rolled back. Preflight is a
smoke check of a fresh runtime, not proof that the live state behaves identically.
It does not test an input-triggered branch or certify visuals/gameplay.

`remove_runtime_child(target)` accepts only an injected node's current handle.
It removes that subtree without replacing its parent. It never promises to undo
prior registrations, resource edits or other side effects. Original game nodes
cannot be removed through this tool.

For durable changes: create a self-initializing component, test/inject it live,
then wire it into persistent construction and test cold startup separately.
Explicit temporary experiments need no source wiring. Respect "do not reload"
throughout. Components needing changes to an existing parent's implementation
may require a reload; report that limitation before building a feature that
cannot be delivered with the available live operations.

## Detached late-injection testing

Use `test_game_action(action="inject_child", run_id=..., candidate_path=".",
name="Grenade", script_path="grenade.gd", properties={...})` to add a component
only in an already-running detached test. Enter gameplay first using existing
`call`/input controls when the component depends on gameplay state. `candidate_path`
is relative to the detached game root; `path` is not an injection alias.
Optional `expected={"class":"Node3D","script":"main.gd"}` checks the parent.
The same constructor/property/load-policy validation and 4 process/3 physics
survival smoke apply. The result includes actual smoke counters and the inserted
handle. This neither applies code live nor requests live-code approval.
A detached failure can have side effects inside that test; stop/restart when needed.

Fast public test actions await up to 300 ms without blocking the host. Completed
results return directly; otherwise poll the returned action ID. A timeout never
resubmits the action. Log reads and Stop remain available while an action is pending.
`action="mouse_button", button_index=3, pressed=true` sends an actual middle-button
event; send `pressed=false` to release. Buttons 1-9 and optional finite numeric
`position={"x":20,"y":30}` are supported. This is not arbitrary InputEvent decoding.

Runtime and test log pagination use exclusive `cursor` and return `next_cursor`.
Use `raw=true` for the initial chronological page, then pass `next_cursor` as
`cursor`. Cursors are session-scoped; there is no `since_sequence` argument.
