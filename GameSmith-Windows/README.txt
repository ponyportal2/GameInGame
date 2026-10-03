GameSmith for Windows
=====================

Double-click GameSmith.exe.

The Godot 4.7.2 Windows runtime is already bundled under runtime\, so GameSmith does not need to download it during normal startup.

Git for Windows must be installed and available on PATH for generated-game repositories.

Pi coding agent is required for GameSmith chat to build or edit games.
Install Node.js/npm, then install the pinned Pi version from PowerShell or Command Prompt:

  npm install -g @earendil-works/pi-coding-agent@1.0.0

After installation, restart GameSmith. If Pi is installed somewhere that is not on PATH,
set the GAMESMITH_PI_BIN environment variable to the full Pi executable path (for example pi.cmd).
