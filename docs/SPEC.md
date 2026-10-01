# Godot LLM Game-Inside-a-Game Platform — Product & Architecture Spec

**Status:** Draft for user review  
**Scope:** v1 architecture and product behavior, with v1.5/v2 roadmap notes  
**Source basis:** Claude brainstorming export + ChatGPT continuation log + brainstorming process requirements  
**Date:** 2026-10-01

---

## 1. Purpose

Build a shipped Godot application for players—not Godot developers—where the player can describe a game in natural language, play it inside the same running host application, and continue asking an LLM to modify it without closing the host.

The host application owns the game library, chat UI, LLM/provider integration, generated-game lifecycle, file/Git tools, runtime logs, and persistent host metadata. Generated games live in isolated per-game workspaces and are loaded into the host at runtime.

The core v1 experience is:

1. Open the host application.
2. Pick an existing generated game or create a new one.
3. Chat with the LLM about what to build or change.
4. The agent edits the current game's files directly.
5. The agent decides when the current edit set is ready and explicitly triggers a reload.
6. The host swaps the generated game to the new version without restarting the host application.
7. The player closes chat and plays the new version.
8. Repeat.

The user should not need Godot knowledge, an editor, or direct code interaction.

---

## 2. Product principles

### 2.1 Conversation directly changes the game

In v1, a normal player request such as “make the enemies faster” is authorization for the agent to act. The agent does not present a patch and wait for confirmation by default.

The agent may ask a clarifying question when the request is materially ambiguous, but routine work should be immediate.

### 2.2 The host is persistent; generated games are replaceable

The host application stays alive while generated games are created, unloaded, and reloaded.

The generated game is disposable runtime content. In v1, each successful reload starts the generated game from a fresh state rather than attempting to preserve current gameplay state.

### 2.3 Keep v1 small and structurally open

v1 intentionally omits several attractive features—state preservation, binary assets, screenshots, autonomous playtesting, rich history UI, preflight validation, strong sandboxing—while leaving clean seams for later versions.

### 2.4 Generated code never owns host data

Generated-game tools are scoped to the current game workspace only. Credentials, transcripts, provider settings, and other host-owned data live outside that workspace and are never exposed through generated-game file tools.

---

## 3. Version scope

## 3.1 v1

v1 includes:

- Exported/shipped Godot host application.
- Player-facing game library.
- New Game, Rename, Delete, Open Game Folder.
- Per-game workspace and Git repository.
- Immediate baseline Git commit at game creation.
- Chat overlay inside the running host.
- Generated games written in GDScript only.
- Both 2D and 3D generated games.
- Direct mounting of generated games into the host's main scene tree.
- Full restart of the generated game after each reload.
- LLM-controlled reload timing.
- Structured file tools, Git tools, runtime-log reading.
- Runtime script-error logging that the LLM may inspect at its discretion.
- Provider/model global defaults plus per-game overrides.
- Supported provider set initially limited to:
  - OpenAI subscription access, if the chosen login path is viable.
  - OpenCode Go subscription/access.
  - Command Code subscription/access.
  - OpenRouter via API key.
- App-owned local credential storage outside game workspaces.
- Persistent readable per-game chat transcript.
- Fresh model context when reopening a game.
- No LLM visual access.
- No LLM-controlled gameplay input.

## 3.2 v1.5

Planned or explicitly allowed for v1.5:

- Best-effort snapshot/restore of host-critical global engine state.
- User-provided binary assets inside a game workspace.
- Persistent per-game model context across app restarts, with compaction/summarization.
- Optional mixed confirmation mode for larger/destructive changes.
- Optional starter scaffolds/templates may be considered.
- On-demand screenshot/vision tool for the LLM.

## 3.3 v2 / later

Planned, possible, or intentionally undecided for v2/later:

- UI for browsing/loading/reverting Git commits.
- Forced Git commit on every successful game launch, in addition to agent-decided commits.
- Static/pre-load validation and compile checks before hot-loading candidate code.
- Compile/load errors fed back into an automatic repair loop; exact retry behavior remains undecided.
- State-preserving reloads.
- Potential host-provided base class instead of the v1 duck-typed contract.
- SubViewport mounting and side-panel layout.
- Separate-process isolation if same-process freezes/crashes become unacceptable.
- Stronger restrictions/sandboxing of generated GDScript.
- Transcript export/import and search.
- Blender model import and Blender MCP support.
- Image generation support.
- Possible `.tscn` support; not committed.
- Possible LLM-controlled or scripted gameplay/playtesting; not committed.
- Player-choice pause behavior, with pause remaining the default.

---

## 4. High-level architecture

The application is divided into five major subsystems.

### 4.1 Host runtime

Responsibilities:

- Mount and unmount the active generated game.
- Compile/load the generated game's entry script at runtime.
- Keep host UI alive across generated-game swaps.
- Report load success/failure.
- Capture supported runtime errors into a bounded log.
- Own the transition back to the game library.

The runtime must be behind a `GameRunner`-style abstraction so future mounting modes—especially SubViewport and separate-process runners—can be added without redesigning the chat or agent layers.

### 4.2 Chat and agent layer

Responsibilities:

- Present the in-game chat UI.
- Maintain the current agent interaction.
- Send player requests to the selected provider/model.
- Expose only structured tools to the LLM.
- Let the LLM decide when to reload.
- Show agent responses and operational results.

The agent layer is not allowed arbitrary terminal/shell execution in v1.

### 4.3 Provider layer

Responsibilities:

- Normalize supported providers behind one provider interface.
- Apply global provider/model defaults.
- Apply optional per-game provider/model overrides.
- Read credentials from host-owned storage, never from game workspaces.

Provider-specific authentication may require different adapters. The architecture must not assume all supported services are OpenAI-compatible merely because some may expose compatible endpoints.

### 4.4 Game storage/history

Responsibilities:

- Own the host-managed games root.
- Discover games by scanning its immediate game folders.
- Create/rename/delete game folders.
- Initialize each game as a Git repository.
- Create the initial baseline commit.
- Expose structured Git operations to the agent.

### 4.5 Host-owned per-game metadata

Responsibilities:

- Store readable chat transcript.
- Store per-game provider/model override.
- Store any other host-owned per-game state needed by the v1 UI/runtime.

This data lives outside the game workspace and is keyed by the game folder name. Renaming/deleting a game must correspondingly migrate/delete its host metadata entry.

---

## 5. Game workspace model

### 5.1 Workspace root

All v1 game workspaces live under one app-managed games directory in the host application's writable data area.

The player does not choose the games root in v1.

The library discovers games by scanning this directory.

### 5.2 Game identity

In v1, the workspace folder name is the game identity and visible game name.

There is no separate stable internal game ID.

Consequences:

- Renaming a game renames its folder.
- Host-owned per-game metadata is migrated to the new folder-keyed name.
- Deleting a game deletes the workspace and associated host metadata after confirmation.

Folder-name sanitization and collision handling are implementation details, but the user-visible name and on-disk folder remain the same logical identity.

### 5.3 New-game initialization

Creating a game must:

1. Create the named workspace folder.
2. Initialize a Git repository.
3. Create an immediate empty/baseline commit, e.g. `Initialize game`.
4. Create the corresponding host-owned metadata entry.
5. Open the game chat.

No `main.gd`, scene, template, or starter scaffold is pre-created in v1.

The first agent generation request creates the source files.

### 5.4 Agent workspace permissions

Within the current game workspace, the v1 agent has full autonomy. It may:

- Read/list/search files.
- Create/write/patch files.
- Move/rename/delete files.
- Reorganize directories.
- Use Git operations.
- Read the host-provided runtime log tool.

The agent must not have file-tool access to:

- Host source code.
- Other game workspaces.
- Credentials.
- Host-owned transcript/settings storage.

Git is the primary v1 recovery mechanism for destructive generated-workspace changes.

---

## 6. Generated-game format

### 6.1 v1 format

Generated games are GDScript-only.

Everything about the generated scene tree is created from code at runtime.

Supported game categories include both:

- 2D (`Node2D`-based or other suitable roots).
- 3D (`Node3D`-based or other suitable roots).

For v1 3D content, visuals must be constructible from code and engine-provided primitives/resources, such as:

- Primitive meshes.
- CSG nodes.
- Materials/shaders created from text/code.
- Lights.
- Cameras.
- Procedurally generated geometry.

v1 does not depend on imported external models, images, sounds, or fonts.

### 6.2 Entry point

Preferred logical convention:

- Root-level `main.gd`.

The exact runtime loading mechanism is spike-gated. If the supported Godot runtime API requires a different internal implementation, the loader should adapt while preserving the logical entry-point convention where practical.

### 6.3 Game/host contract

v1 uses a duck-typed contract.

The entry script may extend any suitable Godot `Node` type. The host requires only that it can instantiate the generated root and add it to the tree.

Optional hooks may later be detected with ordinary runtime checks such as `has_method`, but v1 should not require a host-provided base class.

A base-class contract remains a v2 possibility if lifecycle hooks multiply.

### 6.4 Multi-file support

v1 should support multiple `.gd` files if the runtime spike confirms that independently runtime-loaded generated scripts can reference each other reliably in exported builds.

If that does not work robustly, v1 falls back to a single-file `main.gd` model.

This is a hard spike gate, not a product preference to revisit during implementation.

---

## 7. Runtime loading and swapping

### 7.1 Direct mount

v1 mounts the generated game's root directly into the host's main scene tree.

The generated game receives the real application window and normal Godot input/rendering behavior.

The chat remains a host-owned overlay above it.

### 7.2 Reload semantics

v1 does not preserve generated-game runtime state across changes.

When the LLM chooses to reload:

1. The candidate source files already exist in the workspace.
2. The host attempts to load/instantiate the candidate generated game.
3. On success, the old generated-game instance is replaced.
4. The new generated game begins from its initial state.

The host application itself must remain alive throughout.

### 7.3 Reload timing

Reload timing is controlled by the LLM/agent.

File writes do not automatically trigger reloads.

The agent may make several related edits before reloading and may perform more than one edit/reload cycle inside a single player request if useful.

### 7.4 Candidate load failure

The v1 runtime must surface a failed load attempt to the chat/agent layer.

The desired runtime behavior is to avoid replacing a working generated-game instance with an unlaunchable candidate when technically possible.

However, the later continuation explicitly removed **automatic repair/retry** from v1. Therefore:

- v1 must report load failure clearly.
- v1 does not automatically run a fixed three-attempt repair loop.
- Any automatic retry loop is a possible v2 feature and remains undecided.

The exact mechanics of retaining/restoring the previous working instance across a failed runtime compilation/load are part of the runtime spike because they depend on Godot's actual runtime-loading behavior.

---

## 8. Chat overlay and navigation

### 8.1 Overlay behavior

The chat is a host-owned overlay above the directly mounted game.

When chat opens in v1:

- The generated game is paused.
- Gameplay input is no longer routed to the generated game.
- Chat remains functional while the game is paused.

When chat closes:

- Input returns to the generated game.
- The generated game resumes unless it was replaced by a newly reloaded version, in which case the new version starts fresh.

### 8.2 Open/close controls

v1 provides all three:

- Persistent on-screen chat button.
- Keyboard shortcut to open/toggle chat.
- `Esc` to close chat and return control to gameplay.

The exact non-Escape shortcut is an implementation/UI choice.

### 8.3 Return to library

The chat overlay includes a host-owned **Return to Library** / Home action.

This is the v1 route for safely leaving a running generated game and returning to the game library.

A separate generated-game pause/menu system is not required for this purpose.

---

## 9. Agent behavior and tool surface

### 9.1 Immediate execution

A normal player request authorizes the agent to edit immediately.

The default loop is:

1. Understand the request.
2. Inspect relevant workspace files/logs/Git if needed.
3. Make edits.
4. Decide when to reload.
5. Observe the load result/log information available to it.
6. Respond to the player.

The agent should ask a question only when the request is materially ambiguous enough that acting would likely produce the wrong game behavior/design.

### 9.2 Structured tools only

v1 tools should include, at minimum:

- List files/directories.
- Read file.
- Search workspace text.
- Create/write file.
- Patch file.
- Move/rename file.
- Delete file/directory.
- Git status/diff/history operations needed by the agent.
- Git commit.
- Reload/run generated game.
- Read runtime log.

No arbitrary shell/terminal tool is available in v1.

### 9.3 Git commit policy

v1:

- The LLM decides when to create commits.
- The host creates only the initial baseline commit automatically.
- The UI does not provide a rich commit browser.

v2:

- Preserve agent-decided commits.
- Additionally create a forced commit after every successful generated-game launch.
- Add user-facing commit browsing/loading/reverting.

---

## 10. Runtime error handling and logs

### 10.1 Gameplay/runtime errors

Runtime errors that occur after a game successfully launches should be captured into a bounded host-managed runtime log when the engine makes this possible in exported builds.

The LLM is not invoked automatically just because a runtime error occurs.

The player reports the observed problem in chat, and the LLM may choose to read the runtime log.

### 10.2 Log behavior

The log should:

- Be bounded in size.
- Deduplicate/collapse repeated identical errors where practical.
- Associate entries with the generated-game version/load that produced them.
- Be readable through a structured agent tool.

If direct structured error interception is unavailable in exported builds, reading/parsing Godot's runtime log file is an acceptable fallback if the spike proves it workable.

### 10.3 No v1 autonomous healing

Runtime errors do not trigger automatic LLM calls in v1.

Load errors also do not trigger a fixed automatic retry loop in the final v1 scope.

---

## 11. Chat persistence and context

### 11.1 Transcript persistence

Each game has a persistent readable transcript stored in host-owned per-game data.

The transcript remains visible after restarting the host application.

### 11.2 Model context in v1

Reopening a game in v1 starts a fresh model/agent context.

The durable technical sources of truth are:

- Current game workspace.
- Git history.
- Runtime logs where available.
- The readable transcript, for the human.

The implementation may use an explicit host-created summary to help reconstruction, but no such summary format is a required v1 product contract unless implementation proves it necessary.

### 11.3 Transcript UI scope

v1 transcript management is intentionally minimal.

v1 does not include:

- Transcript search.
- Export/import.
- Branching/versioning UI.

v2 adds transcript export/import and search.

---

## 12. Provider and credential model

### 12.1 Provider selection

v1 has:

- One global default provider/model setting.
- Optional per-game provider/model override.
- No requirement for per-message provider switching.

Games without an override follow the current global default.

### 12.2 Initial supported providers

The user specified the initial target set as:

- OpenAI subscription.
- OpenCode Go subscription/access.
- Command Code subscription/access.
- OpenRouter API key.

The provider layer must accommodate different authentication and API shapes behind a common host interface.

### 12.3 Credential storage

v1 stores credentials in an app-owned local credentials file outside all game workspaces.

Generated-game tools and generated code must not be given the path or direct access to this file through host tooling.

OS keychain integration is not required in v1.

This spec does not promise strong at-rest secrecy from a local attacker. The exact local protection/encryption approach is an implementation/security decision.

---

## 13. Game library UX

### 13.1 Startup

The host starts on a simple game-library screen.

It shows:

- Existing game workspaces discovered under the app-managed games root.
- **New Game**.

No thumbnails, tags, advanced sorting, or rich metadata are required in v1.

### 13.2 Open existing game

Selecting an existing game should launch its latest usable/working state and open the normal play/chat experience.

The implementation must define a reliable way to identify that usable state from workspace/Git/host runtime metadata. Because the brainstorming did not settle the exact persistence mechanism, this is an implementation decision constrained by the requirement that reopening a broken/incomplete edit must not silently destroy the player's last known working experience when recovery information exists.

### 13.3 Rename

Rename changes the workspace folder name and migrates the corresponding host-owned per-game metadata key.

### 13.4 Delete

Delete requires confirmation, then removes:

- The game workspace folder.
- The corresponding host-owned per-game metadata.

### 13.5 Open Game Folder

v1 includes an action to reveal/open the current game workspace in the user's file manager.

---

## 14. Visual and playtesting capabilities

### 14.1 v1

The LLM does not receive game screenshots or captured frames.

The LLM cannot synthesize gameplay input, click through the generated game, or autonomously play it.

The LLM's feedback sources are limited to:

- Source files.
- Git information.
- Runtime/load results.
- Runtime logs.
- Player descriptions.

### 14.2 v1.5 / v2

v1.5 adds an on-demand screenshot/vision tool.

LLM-controlled gameplay or richer automated playtesting is only a possible v2 feature and remains undecided.

---

## 15. Binary assets and generated media

### 15.1 v1

No user-provided binary assets are part of the supported v1 content model.

Generated games should rely on:

- Procedural graphics.
- Primitive 2D/3D geometry.
- Built-in/default engine resources.
- Procedural audio if needed.
- Shader source expressed as text/code where useful.

### 15.2 v1.5

Allow user-provided binary assets in the game workspace, subject to whatever runtime-loading path the Godot spike validates.

### 15.3 v2/later

Possible later additions:

- Generated images.
- Blender import.
- Blender MCP integration.
- Other generated/imported media pipelines.

---

## 16. Security and isolation

### 16.1 v1 reality

v1 generated GDScript runs in the same Godot process as the host and therefore is not a strong security boundary.

Potential failure modes include:

- Infinite loops/freezes taking down the host UI.
- Crashes taking down the host process.
- Generated code changing global engine state.
- Generated code using powerful Godot APIs beyond the intended game behavior.

v1 deliberately accepts this risk to keep the first architecture small.

### 16.2 Workspace isolation

The host agent tools are still strongly scoped even though runtime GDScript is not fully sandboxed:

- Agent file tools operate only in the current game workspace.
- Credentials and host metadata are stored elsewhere.
- Other game workspaces are outside the tool boundary.

### 16.3 Global engine state

v1 does not implement snapshot/restore of global engine state.

v1.5 adds best-effort restoration of host-critical state.

v2 may prevent/restrict dangerous global mutations more directly.

### 16.4 Stronger sandboxing

API restriction, static analysis, process isolation, and related hardening are v2/later concerns.

---

## 17. Required feasibility spikes before implementation is considered complete

These are architecture gates derived from the brainstorming. They must be answered early because they determine whether the preferred v1 shape is technically valid.

### Spike A — runtime GDScript compilation/loading in exported builds

Verify the exact supported mechanism for loading LLM-written GDScript source at runtime in a packaged/exported application.

Must establish:

- Raw source can be loaded/compiled at runtime.
- Errors can be detected and returned programmatically.
- Instances can be created and mounted without the Godot editor.

If this fails, the runtime-loading architecture must be revised before product implementation proceeds. Packaging the full editor binary is only a last-resort fallback concept from brainstorming, not a selected requirement.

### Spike B — multi-file generated games

Verify that runtime-loaded generated scripts can reliably reference/load other generated scripts from the same workspace in exported builds.

Result determines:

- Pass: v1 supports multi-file games.
- Fail: v1 uses single-file `main.gd`.

### Spike C — paused game with live host chat

Verify that opening the host chat can pause generated gameplay while keeping the host-owned chat UI, networking/provider calls, and agent operations functional.

### Spike D — runtime error capture in exported builds

Verify whether the host can capture generated-script runtime errors in a structured form after launch.

If not, test fallback access to Godot's log output and determine whether it is reliable enough for the v1 `read runtime log` tool.

### Spike E — base-class resolution for v2

Not a v1 blocker. Investigate whether runtime-compiled scripts can cleanly extend a host-owned generated-game base class. This informs the possible v2 contract.

---

## 18. Success criteria for v1

v1 is successful when all of the following are true:

1. A non-Godot user can launch the host application and create a named game from the library.
2. The first chat request can generate a playable 2D or 3D GDScript-only game without closing the host.
3. The player can reopen chat, request a modification, and see a newly loaded version in the same host process.
4. The LLM can make multi-file edits if the multi-file spike passes; otherwise the fallback single-file format works reliably.
5. Chat remains available as the control/recovery surface while gameplay is paused.
6. Generated-game tools cannot access host credentials, host metadata, or other game workspaces.
7. Each game has Git history and an initial baseline commit.
8. The player can rename/delete a game and return from gameplay to the library.
9. Runtime errors are available through the agreed log mechanism when technically supported by the spike.
10. The system works as an exported/shipped application, not only inside the Godot editor.

---

## 19. Explicit non-goals for v1

The following are intentionally out of scope:

- Gameplay state preservation across reloads.
- `.tscn` as a required generated format.
- Imported models.
- User binary assets.
- Generated image/media pipelines.
- Screenshot/vision feedback to the LLM.
- LLM-controlled gameplay input.
- Automatic post-error self-healing/retry loop.
- Pre-load static analysis/validation.
- Separate-process isolation.
- Strong GDScript sandboxing.
- OS keychain integration.
- Custom games-root selection.
- Rich game-library metadata/thumbnails/tags.
- Commit-history UI.
- Transcript search/export/import.
- Per-message provider/model switching.

---

## 20. Open implementation decisions

The brainstorming deliberately stopped before trivial implementation-level questions. The following should be decided during implementation planning or the required spikes, not by reopening product scope:

- Exact Godot runtime API used to compile/load generated scripts.
- Exact method for preserving the previous working game when a candidate load fails.
- Exact representation of “latest usable/working state” across application restarts.
- Exact runtime-log interception/fallback mechanism.
- Exact keyboard shortcut for opening chat.
- Folder-name sanitization and duplicate-name behavior.
- Exact local credentials-file format and at-rest protection.
- Exact provider adapter/auth implementation for each named service.
- Exact transcript storage format.
- Exact Git command/API implementation behind structured tools.
- Exact UI styling/layout.

These are implementation choices unless a spike proves they force an architectural change.

---

## 21. Decision precedence and superseded notes

Where the earlier Claude session and later ChatGPT continuation differ, the later explicit user decision wins.

Important supersession:

- Earlier Claude-session note: load errors trigger up to three automatic LLM repair attempts.
- Later user correction: **not in v1**; automatic repair/retry is only a possible v2 feature and remains undecided.

Other later continuation decisions—v1.5 global-state restoration, v1/v1.5 binary-asset split, transcript-context behavior, provider override behavior, workspace/library behavior, credential storage, immediate execution, LLM-controlled reloads, screenshot/playtesting scope, and navigation—likewise take precedence over earlier proposals where applicable.

---

## 22. Recommended implementation decomposition

This spec covers the whole product architecture, but implementation should be planned in dependency order:

1. **Runtime feasibility spikes** — exported runtime loading, multi-file linking, pause/chat coexistence, error capture.
2. **Runtime core** — mount/unmount/reload contract and direct runner.
3. **Workspace + Git storage** — game roots, baseline commits, file/Git tool boundaries.
4. **Game library + host metadata** — create/open/rename/delete, transcript/settings storage.
5. **Chat/agent loop** — immediate execution, structured tools, reload tool, runtime-log tool.
6. **Provider layer** — global defaults, per-game overrides, credentials, provider adapters.
7. **Integration hardening** — exported-build testing, crash/failure UX, boundary tests.

The written implementation plan should split these into concrete milestones after this spec is approved.

---

## 23. Self-review results

This spec was checked for:

- **Placeholders:** No unresolved product requirement is left as an accidental placeholder. Items that are genuinely implementation- or spike-dependent are explicitly labeled as such.
- **Internal consistency:** Later decisions override earlier brainstorming where conflict existed, especially automatic repair/retry behavior.
- **Scope:** v1 remains intentionally narrow despite covering multiple subsystems; the implementation decomposition isolates them while preserving one coherent product contract.
- **Ambiguity:** Major behavior is explicit. Remaining ambiguity is restricted to implementation mechanics or spike-gated Godot capabilities.

