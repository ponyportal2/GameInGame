#!/usr/bin/env python3
"""Verify the committed Windows release folder is structurally runnable."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
package = root / "GameSmith-Windows"
required = {
    package / "GameSmith.exe",
    package / "GameSmith.pck",
    package / "runtime" / "Godot_v4.7.2-stable_win64.exe",
    package / "README.txt",
    package / "THIRD_PARTY_NOTICES.md",
}

if not package.is_dir():
    raise SystemExit(f"missing {package.name}/")
missing = sorted(str(path.relative_to(root)) for path in required if not path.is_file())
if missing:
    raise SystemExit("missing required Windows folder files: " + ", ".join(missing))

launcher = package / "GameSmith.exe"
runtime = package / "runtime" / "Godot_v4.7.2-stable_win64.exe"
pck = package / "GameSmith.pck"

if launcher.read_bytes()[:2] != b"MZ":
    raise SystemExit("GameSmith.exe is not a Windows PE executable")
if runtime.read_bytes()[:2] != b"MZ":
    raise SystemExit("bundled Godot runtime is not a Windows PE executable")
if runtime.stat().st_size < 100 * 1024 * 1024:
    raise SystemExit(f"bundled Godot runtime looks truncated: {runtime.stat().st_size} bytes")
if pck.stat().st_size <= 0:
    raise SystemExit("GameSmith.pck is empty")

print(
    "PASS: GameSmith-Windows/ is self-contained "
    f"(launcher={launcher.stat().st_size} bytes, "
    f"pck={pck.stat().st_size} bytes, runtime={runtime.stat().st_size} bytes)"
)
