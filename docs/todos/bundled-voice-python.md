# Bundled voice recognition runtime

- [x] Regress included-runtime installation, package isolation and removal of the Python setting.
- [x] Bundle pinned Windows x64 Python and pip with upstream licenses/provenance.
- [x] Use included Python for installation and transcription; retain on-demand packages/models.
- [x] Verify source/PCK execution and a real dependency installation without system Python.
- [x] Update user documentation and rebuild the Windows package.

No model weights in the repository. No global Python/packages/settings changes.

## Implementation

Official CPython 3.13.17 embeddable ZIP and pip 25.3 wheel, with SHA-256 metadata
in `tools/voice/bundled.json`. Runtime extraction verifies the bundled hashes;
Python runs with `-I`. Explicit install invokes bundled pip with `--isolated`,
`--only-binary=:all:` and an app-private package target/cache. Explicit reinstall
removes only private packages, preserving models and the interpreter. Legacy
system-Python installation markers require one new Install. No executable field
remains in Voice settings. Other platforms have no included runtime yet.

Complete Python license and all 45 pip/vendor license/provenance files are
mirrored into the source and Windows distribution, tested byte-for-byte against
the archives, and exempted from Git newline conversion. Both third-party notices
and user documentation identify the components. Export preset and its inventory
generator both include the archives, manifest and licenses.

Approximate PCK increase: 12.8 MiB. No model weights are shipped.

## Verification (2026-11-08)

- TDD red: the new archive/manifest test failed before the bundle was added.
- `node:voice`: 15 deterministic Python tests through the shipped worker source,
  covering archive hashes/license mirrors, included interpreter invocation,
  failed-install retry, successful reinstall, model/runtime preservation,
  cancellation, audio bounds and IPC.
- First source runtime test failed because its empty PATH also hid Windows
  PowerShell, which existing JsonStore requires. The fixture now keeps Windows
  tools while excluding system Python/WindowsApps. Exact failed-only rerun passed:
  `%TEMP%/gamesmith-verify-Yys8aP/results.json` (2/2 entries).
- Focused run: `%TEMP%/gamesmith-verify-idBhOi/results.json`, 11 selected / 13 entries,
  12 passed and one failed. Voice runtime (8 assertions), voice UI (62), picture
  UI (29), UI layout (30), workspace store (47), library actions (17), Pi notices,
  archive/worker tests and package contents/structure passed. The sole failure
  caught the unupdated export-filter generator; production preset was already
  updated. Fixed generator; failed-only rerun passed 24/24 verifier assertions,
  2/2 entries: `%TEMP%/gamesmith-verify-v0Nant/results.json`.
- Final rebuild and source/package checks: 5/5 entries, 19 assertions, no failures:
  `%TEMP%/gamesmith-verify-YUQ4aI/results.json`. Packaged runtime actually extracts
  and executes its own interpreter, not merely an archive-existence assertion.
- Real dependency install, isolated user data and no system Python on PATH:
  `%TEMP%/gamesmith-voice-bundle-5786163323024aacb068ff705e9b6870/recognition-install.log`.
  faster-whisper, CTranslate2, PyAV and ONNX Runtime installed/imported successfully.
- Final PCK with those real packages: 10 passing runtime assertions, exit 0:
  same directory's `packaged-recognition.log`. Includes legacy marker rejection,
  isolated interpreter/native stdlib, bundled pip, native dependency imports,
  production worker/silent audio IPC and worker cleanup.
- Final PCK rendered voice/picture UI: 62 passed / 0 failed, exit 0:
  `%TEMP%/gamesmith-voice-bundle-ui-8f232ec547c3438191a77ed2ec062ea1/packaged-voice-ui.log`.
- License-only cleanup excluded two Python modules whose directory was named
  `licenses` but which were not license files. Rebuilt again; archive/license
  regression and package contents/structure passed, 5/5 entries, no failures:
  `%TEMP%/gamesmith-verify-5rbWQw/results.json`. Runtime source was unchanged.

No real coding-provider calls, model download, live microphone recording or
speech-model inference in this patch's acceptance. No exhaustive full-suite run;
focused consumers plus real included-runtime/package acceptance were used.

Final tested PCK SHA-256: `1c1bc209647a98bfaff76885df586cc2f03d7cdf4f780b8ec395e8f793831db3`.
