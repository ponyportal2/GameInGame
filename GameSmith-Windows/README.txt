GameSmith for Windows
=====================

Double-click GameSmith.exe.

The Godot 4.7.2 Windows runtime is already bundled under runtime\, so GameSmith does not need to download it during normal startup.

Git for Windows must be installed and available on PATH for generated-game repositories.

Choose Pi or Command-code when creating a game. Install the harness you want to use.
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
