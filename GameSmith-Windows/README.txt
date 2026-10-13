GameSmith for Windows
=====================

Double-click GameSmith.exe.

The Godot 4.7.2 Windows runtime is already bundled under runtime\, so GameSmith does not need to download it during normal startup.

Git for Windows must be installed and available on PATH for generated-game repositories.

Choose Pi, Command-code, OpenCode, Codex, Cline, Cursor, Grok Build, AGY (experimental), Kimi Code, or Kiro CLI when creating a game. Install the harness you want to use.
Install Node.js/npm, then install the pinned Pi version from PowerShell or Command Prompt:

  npm install -g @earendil-works/pi-coding-agent@1.0.0

After installation, restart GameSmith. If Pi is installed somewhere that is not on PATH,
set the GAMESMITH_PI_BIN environment variable to the full Pi executable path (for example pi.cmd).

For Command-code games:

  npm install -g command-code

Configure your model and provider in the command-code CLI. GameSmith leaves model,
provider, reasoning, and compaction settings to Command-code and disables its own
agent settings for those games. Rendered-test permission remains available.
Node.js must be on PATH. For a custom installation, set GAMESMITH_COMMAND_CODE_BIN
to the command-code.cmd shim or dist/index.mjs entry point. Existing games use Pi.

For OpenCode games:

  npm install -g opencode-ai

Configure your model/provider in the OpenCode CLI. GameSmith leaves all model,
provider and compaction settings to OpenCode. Testing and automatic reload approval
remain available. Node.js must be on PATH. For a custom installation, set
GAMESMITH_OPENCODE_BIN to the opencode executable or npm shim. Each game resumes
its own native OpenCode session. Restart GameSmith after updating the package.

For Codex games:

  npm install -g @openai/codex

Sign in and configure the Codex CLI. Model, provider, reasoning and compaction remain
owned by Codex; host testing and reload preferences remain available. Node.js must
be on PATH. GAMESMITH_CODEX_BIN can select a custom executable or npm shim.
Each game resumes its own native thread. If a thread cannot be resumed, retry or
use Settings > This game > Start new Codex session and confirm. The previous
session reference, readable chat and game files are kept. Restart GameSmith after
updating the package.

For Cline games:
  npm install -g cline
Sign in and select a model in Cline, then choose Cline for a new game or in
Settings > This game > Coding harness. Cline owns provider/model/reasoning and
compaction; GameSmith's testing and reload preferences remain available. Native
ACP sessions persist per game and resume when reopening or switching back.
Reload approval waits without a timer. Stop retains a healthy backend; stalled
cancellation force-stops it after five seconds. A failed resume can be recovered
with Settings > This game > Start new Cline session (confirmation preserves the
old reference and chat). Restart GameSmith after updating this package.

For Cursor games:
Install Cursor Agent CLI: https://cursor.com/docs/cli/installation
The desktop app alone is insufficient. Sign in with cursor-agent login and
then select Cursor in GameSmith. Cursor uses Auto (default[]) for GameSmith ACP sessions. GameSmith does not synchronize the model selected in the desktop
editor or interactive CLI, so those choices may differ. The standard
Windows cursor-agent installation is detected without requiring PATH changes;
GAMESMITH_CURSOR_BIN can select a custom entry point. Node.js is also required.
Cursor owns model/provider/reasoning and compaction. GameSmith testing and reload
preferences remain available. Ordinary messages reuse the native ACP backend;
reopening or switching back resumes the saved native conversation. Stop retires
the backend to clear cancelled MCP calls, then the next message resumes history.
Reload approval waits without a timer. Failed resume recovery is available at
Settings > This game > Start new Cursor session, preserving the old reference
and readable chat. Restart GameSmith after updating this package.

For Grok Build games:
Install and sign in to Grok Build: https://docs.x.ai/build
Choose Grok Build for a new game or in Settings > This game > Coding harness.
GameSmith uses grok.exe, including the standard %USERPROFILE%/.grok/bin install,
or GAMESMITH_GROK_BUILD_BIN. It never uses the ambiguous agent command to
choose Cursor or Grok Build. Native ACP identity checks reject mismatched overrides.
Model/provider/reasoning and compaction stay owned by Grok Build; host testing
and reload preferences remain available. Messages reuse one ACP backend and
native session. Reopen/switch back resumes history. Stop retires the backend,
with a five-second fallback, and the next message resumes the same session.
Reload waits for player approval. Start new Grok Build session in Settings
archives an unresumable reference while keeping readable chat and game files.
Restart GameSmith after updating the package.

For AGY games (EXPERIMENTAL):
Install/sign in to Antigravity CLI and select its model natively.
Choose AGY (experimental) when creating a game or in Settings > This game.
Discovery uses agy.exe at %LOCALAPPDATA%/agy/bin, agy on PATH, or GAMESMITH_AGY_BIN.
Model/provider/reasoning and compaction remain native-owned.
Ordinary requests reuse a stream-JSON process and explicit conversation ID.
Stop kills its backend/MCP tree; reopen, switch back and the next message resume
the saved conversation. Start new AGY session in Settings archives its reference.
GameSmith MCP provides workspace, test, reload and Git tools. Reload waits for
player approval unless automatic reload approval is enabled.
Fixture tests and installed CLI startup/MCP discovery/explicit resume passed.
Live model invocations returned "User location is not supported for the API use".
No successful model/game acceptance or native tool-hook execution was verified.
See README.md's experimental AGY section for the exact verification limits.

For Kimi Code games:
Install native Kimi Code CLI: https://moonshotai.github.io/kimi-code/
Configure login/provider/model in Kimi Code, then choose Kimi Code in GameSmith.
The standard %USERPROFILE%/.kimi-code/bin/kimi.exe installation is detected even
without PATH. GAMESMITH_KIMI_BIN can specify another native executable.
GameSmith uses persistent ACP sessions, resumes explicit per-game history and
leaves model, provider, reasoning and compaction to Kimi. Node.js is required.

For Kiro CLI games:
Install native Kiro CLI: https://kiro.dev/docs/cli/
Choose Kiro CLI in GameSmith. The standard %LOCALAPPDATA%/Kiro-Cli/kiro-cli.exe
installation is detected without PATH; GAMESMITH_KIRO_BIN selects another binary.
Kiro CLI 2.30.0 is tested using its V2 ACP engine. Node.js is required.
Kiro owns model/provider/reasoning/compaction. Save a model as Kiro's default with
/model set-current-as-default or kiro-cli settings chat.defaultModel <model-id>.
Without a saved native default, this installation uses Auto. GameSmith does not
inherit temporary model choices from other interactive conversations.
Messages reuse one native conversation; reopen, rename and Stop resume its exact
ID. Reload waits for GameSmith approval unless automatic approval is enabled.
Start new Kiro session in Settings archives the reference without deleting history.
Host headless tests, reload approval and automatic reload approval remain available.
