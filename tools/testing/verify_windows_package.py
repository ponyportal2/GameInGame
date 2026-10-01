#!/usr/bin/env python3
"""Verify the committed Windows release ZIP is structurally runnable."""
from pathlib import Path
import sys
import zipfile

root = Path(__file__).resolve().parents[2]
package = root / "GameSmith-Windows.zip"
required = {
    "GameSmith-Windows/GameSmith.exe",
    "GameSmith-Windows/GameSmith.pck",
    "GameSmith-Windows/runtime/Godot_v4.7.2-stable_win64.exe",
    "GameSmith-Windows/README.txt",
}

if not package.is_file():
    raise SystemExit(f"missing {package.name}")
if package.stat().st_size >= 100 * 1024 * 1024:
    raise SystemExit(f"{package.name} is too large for ordinary GitHub Git: {package.stat().st_size} bytes")

with zipfile.ZipFile(package) as zf:
    bad = zf.testzip()
    if bad:
        raise SystemExit(f"corrupt ZIP entry: {bad}")
    names = set(zf.namelist())
    missing = sorted(required - names)
    if missing:
        raise SystemExit("missing required package entries: " + ", ".join(missing))

print(f"PASS: {package.name} is intact, self-contained, and {package.stat().st_size} bytes")
