# Live parameter iteration

GameSmith exposes `inspect_runtime` and `set_properties` through every harness.
They operate on the player's current generated game beneath `active_game`,
not the host UI or a separate test process. No game hooks are required.

For a parameter edit: inspect, edit persistent source, headlessly test that
source, patch existing instances, and check the results. Reload remains the
fallback for changes that cannot be represented as supported property writes,
unless the player says not to reload. That constraint remains binding when
inspection or patching fails: report the blocker. An explicitly temporary
live-only experiment needs no source edit or headless source test.
Runtime patches do not save source or advance the last working snapshot.
Loaded code/defaults also stay unchanged: newly spawned instances can retain
their old defaults even after the source file is edited. Patch a live spawner's
configuration when the game uses one, or reload when future spawns must change.

```json
{"root":".","depth":3,"group":"enemies","properties":["speed","health"]}
```

Inspection returns a flat `nodes` array containing only `handle`, engine `class`,
requested `values`, and `property_errors` when a requested read fails. A handle
contains a game-relative `path`, string `instance_id`, and string
`game_generation`. Copy it verbatim; never infer IDs or omitted paths.
Generation identifies the current game root; replacing or unloading the game
invalidates its handles. Renaming/reparenting also invalidates the old path.
A successful mutation returns the current handle.

For property discovery, inspect one representative node:

```json
{"root":"Enemy0","discover_properties":true}
```

Discovery defaults to depth 0 and limit 1 (at most 3 nodes per page), and additionally returns `script`,
`scene_file_path`, up to 32 groups, and up to 64 `available_properties` descriptors
with `properties_truncated`. Inspector category/group/subgroup headings are
excluded. Untyped fields are listed as Variant; values are only read on request.
An explicit depth overrides the discovery default; ordinary inspection defaults
to depth 3. Property discovery can still be large: use one node at a time.

Filters `class` (engine class, including inheritance), `script` (exact resource
path from discovery), and `group` combine with AND. Defaults: root `.`, offset 0,
limit 100. Depth is 0..8, limit 1..100, offset 0..1000; each request visits at most
1000 nodes. At most 16 properties can be requested per node.

```json
{"class":"Polygon2D","depth":3,"properties":["color"],"offset":0,"limit":50}
```

`truncated_by` distinguishes incomplete results:

- `result_limit`: another matching node was found; `has_more=true` and
  `next_offset` continues after this page. Offset counts matches, not visited nodes.
- `depth_limit`: children were omitted; increase depth or narrow the root.
- `traversal_limit`: the 1000-node traversal/storage bound omitted nodes; narrow
  the root. Pagination does not bypass the traversal bound.

`truncated` is true if any reason is present. `next_offset` is null and
`has_more=false` unless another result was actually found within the traversal.
Depth/traversal reasons may coexist with result pagination; exhausting pages
then does not prove all nodes in the game were inspected.
Pages are best effort over the live tree, not a snapshot. Keep the same query,
deduplicate identities, and restart inspection if `game_generation` changes.
Spawning/removal/reparenting between calls can cause skipped or repeated nodes.
For stable trees, an exact-size final page has no false continuation.

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

Report runtime readback, visual verification, and persistence separately. A
successful write does not prove rendered appearance, later frames, future
instances, or source changed. For OpenCode overflow saved outside the workspace,
do not follow native Task/read instructions: those routes are unavailable.
Retry inspection with smaller pages/fewer properties/narrower filters. Never
blindly repeat a mutation whose response was truncated.

Script reload, scene replacement, state migration, expression evaluation, and
automatic impact analysis are outside this implementation.

For a later adjustment, inspect fresh values and handles first. Start with the
relevant engine class and known properties. For brightness, for example, inspect
`DirectionalLight3D` with `properties:["light_energy"]`. Shared mutation values
apply identically to every target; use separate calls for different desired
values. Immediate readback is sufficient to confirm the write, while visual
verification is a separate check.

`rg_search` uses installed system `rg` without a shell or arbitrary flags. A
missing executable returns an explicit error. All harnesses expose it:

```json
{"target":"source","pattern":"light_energy|ambient_light","glob":"*.gd","limit":20}
```

Source results contain workspace-relative `path`, `line`, and matching `text`.
Optional `path` narrows the search inside the workspace; escaping paths and
external symlinks/junctions are rejected, and recursive search does not follow
links. Git and Godot metadata are excluded from ordinary recursive search.
Regular expressions follow rg syntax; `case_sensitive:false` ignores case.

```json
{"target":"runtime","pattern":"Fill|Sun","class":"DirectionalLight3D","properties":["light_energy"],"limit":20}
```

Runtime search obtains one fresh compact inspection page (100 nodes) and feeds
its JSON records to rg through stdin. Matches return complete node records and
their observed handles, not reconstructed IDs. `root`, `depth`, `class`, `script`,
`group`, and `properties` narrow inspection. Default depth remains 3; a pattern
alone cannot discover nodes beyond that depth or the inspection traversal bound.
`offset`/`limit` paginate matching records in this page, using `next_offset` when
`has_more`. Separately, `runtime_next_offset` continues inspection: pass it as
`runtime_offset` and reset match offset to 0. `runtime_truncated_by` retains the
inspection limitations. Pages can shift as the game changes.

Textual GameSmith results across the harness adapters are bounded to 50 KiB of
UTF-8 JSON or 2,000 logical lines, whichever comes first. Logical lines include
JSON structure and newlines inside string values. Image blocks are separate.
Oversized results become valid JSON with `output_truncated`, original sizes,
truncation reasons, a short incomplete preview, and recovery guidance. Mutation
success/failure counts and diagnostic delivery identity survive truncation.
Preview text is not a complete record or usable handle. Narrow filters and
paginate; do not blindly repeat a mutation that may already have applied.
Native vendor tools retain their own output policies.
