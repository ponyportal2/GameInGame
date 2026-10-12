GameSmith for Windows
=====================

Double-click GameSmith.exe.

The Godot 4.7.2 Windows runtime is already bundled under runtime\, so GameSmith does not need to download it during normal startup.

Git for Windows must be installed and available on PATH for generated-game repositories.

Choose Pi, Command-code, OpenCode, Codex, or Cline when creating a game. Install the harness you want to use.
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
