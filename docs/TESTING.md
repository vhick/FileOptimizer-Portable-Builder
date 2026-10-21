# Windows acceptance test (use disposable copies)

1. Extract the artifact into `X:\PortableApps\`. Confirm the root EXE is exactly `X:\PortableApps\FileOptimizerPortable\FileOptimizerPortable.exe`.
2. Refresh the PortableApps Menu: `FileOptimizer Portable` should appear in Utilities with the developer's icon.
3. Start via the root launcher only. Look at **Options** and confirm the program runs without asking for an installer.
4. Change an innocuous option (such as language or log level), close fully, and confirm the relevant INI is under `Data\Settings`.
5. Reopen and check that your option persisted.
6. Copy a small PNG and PDF to a temporary test directory; optimize only the COPIES. Confirm optimization completes and files remain readable.
7. Confirm bundled `Plugins64` is still present and that tools were actually used in the output logs.
8. Check `Data\Logs` and `Data\Temp` for application-owned data; ensure normal settings did not appear in `%USERPROFILE%`.
9. Check `%APPDATA%`, `%LOCALAPPDATA%`, and registry with a before/after trace utility on a clean account. **Do not delete unrelated folders or registry keys.**
10. Exit; replace only root EXE + `App/` + `Other/` with a fresh build. Keep `Data/`. Start again and confirm settings remain.
11. Optional: move full portable folder to another Windows PC and repeat steps 3-7.

NOTE: FileOptimizer may change file metadata and ability to edit certain document formats, even when the visible output is lossless. Retain originals.
