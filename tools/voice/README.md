# Included voice runtime

The Windows x64 app ships the official CPython 3.13.17 embeddable distribution
and pip 25.3 wheel. `bundled.json` records upstream URLs and SHA-256 hashes;
the deterministic voice tests check the actual bytes and license copies.
The archives are unmodified. No Whisper model weights are shipped.

Godot verifies the archives before extracting them into the versioned
`user://host/voice/python-3.13.17` directory. It runs that interpreter with `-I`.
On explicit Install, pip runs directly from its wheel with `--isolated` and
installs binary wheels into `user://host/voice/environment` using `--target`.
This does not need pip/venv support in the embedded distribution, a system Python,
or changes to user Python configuration. Explicit reinstall replaces packages
only; models remain in the separate `models` directory.

To update, download official artifacts using the manifest URLs, update their
versions/hashes, and recopy all upstream licenses from the archives. Python's
complete `LICENSE.txt` (including bundled-component notices) is retained as
`licenses/PYTHON-LICENSE.txt`. pip's license and vendored license/provenance files
retain their archive paths under `licenses/pip/`. The Windows distribution has
identical copies under `GameSmith-Windows/licenses/voice/`. Update both top-level
third-party notices and run source/package/runtime checks before delivery.

Recognition dependencies are installed on demand; their wheel metadata/licenses
remain in the private package directory. This runtime does not support other
operating systems or CPU architectures yet.
