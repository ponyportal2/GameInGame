# Live parameter iteration

GameSmith exposes `inspect_runtime` and `set_properties` through every harness.
They operate on the player's current generated game beneath `active_game`,
not the host UI or a separate test process. No game hooks are required.

For a parameter edit: inspect, edit persistent source, headlessly test that
source, patch existing instances, and check the results. Reload remains the
fallback for changes that cannot be represented as supported property writes.
Runtime patches do not save source or advance the last working snapshot.
Loaded code/defaults also stay unchanged: newly spawned instances can retain
their old defaults even after the source file is edited. Patch a live spawner's
configuration when the game uses one, or reload when future spawns must change.

```json
{"root":".","depth":3,"group":"enemies","properties":["speed","health"]}
```

Inspection returns a flat `nodes` array. Each entry includes `handle`, engine
`class`, `script`, `scene_file_path`, groups, bounded `available_properties`,
requested `values`, and `property_errors`. `handle` contains a game-relative
`path`, string `instance_id`, and string `game_generation`. Copy it verbatim.
Generation identifies the current game root; replacing or unloading the game
invalidates its handles. Renaming/reparenting a node also invalidates its old
path. A successful mutation returns the current handle.

Filters `class` (engine class, including inheritance), `script` (exact reported
resource path), and `group` combine with AND. Defaults: root `.`, depth 3,
limit 100. Depth is 0..8, limit 1..100, and traversal visits at most 1000 nodes.
`truncated` means the depth, traversal, or result bound omitted nodes. Narrow
the root/filter to inspect further. At most 16 requested properties, 64 available
property descriptors, and 32 groups are returned per node. Discovery lists
untyped properties as Variant; reading them requires explicitly requesting them.

```json
{
  "targets":[{"path":"Enemy0","instance_id":"12345","game_generation":"12300"}],
  "values":{"speed":120,"position":{"type":"Vector2","x":12,"y":34}}
}
```

Mutation accepts 1..100 unique explicit handles and 1..16 shared property
values. It rejects parent traversal, absolute paths, NodePath subnames, stale
identities, and targets queued for deletion (including queued ancestors).
Supported values are booleans, finite numbers of magnitude at most
9007199254740991 (integers must also be exact), strings/StringNames up to
1024 characters, and these tagged values:

- `{"type":"Vector2","x":1,"y":2}`
- `{"type":"Vector3","x":1,"y":2,"z":3}`
- `{"type":"Color","r":1,"g":0.5,"b":0,"a":1}`

No automatic string-to-number conversion occurs. Untyped fields use their
current value type. Objects, resources, arrays, dictionaries, nulls, and other
Godot value types are unsupported. No expressions or arbitrary methods execute
through this API, though normal Godot property getters/setters can execute game
code and cause side effects. This is an editing boundary, not a security sandbox.

Each target's property names/types are validated before its first write.
Targets execute independently on the host main thread. Results include `matched`
(requested targets), `changed` (targets whose writes and readback completed),
`failed`, and per-target `ok`, `applied` property names, `values`, and `error`.
The aggregate `ok` is false if any target fails. `changed` is not a count of
numerically different values. A failed target can still have applied writes;
there is no rollback. Readback occurs after all writes to that target, so setter
clamping and changes to other written fields are visible. It proves the values
at that instant only; gameplay may overwrite them next frame. Errors raised by
game code remain available through `read_runtime_log`.

Script reload, scene replacement, state migration, expression evaluation, and
automatic impact analysis are outside this implementation.
