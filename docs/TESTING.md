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


## v1.2 TraceGuard portability test

1. Make sure FileOptimizer is closed. Keep the full existing Data folder when updating.
2. Start only `FileOptimizerPortable.exe`. Change the FileOptimizer Options (e.g. appearance/Hide ads).
3. Optimize copies of two or more disposable files and wait until each finishes.
4. Close FileOptimizer and wait for the launcher to exit.
5. Open `Data\Logs\TraceGuard-*.txt` (the latest filename is recorded in `Data\TraceGuard\LatestReport.txt`).
6. Inspect `FILESYSTEM CREATED`, `REGISTRY CREATED`, and `REGISTRY CHANGED` lines. They may include host paths, not necessarily traces written by FileOptimizer; before/after comparisons do not establish process ownership.
7. Check `Data\TraceGuard\Recovered` for safely relocated newly created FileOptimizer-named folders.
8. Check `Data\Browser\WebView2` if the app invoked a supported WebView2 runtime.
9. Reopen the app and check that settings and logs in Data remain intact.
10. If a host remnant remains, send the relevant report lines. Do not delete shared registry keys or system cache folders.

**Crash recovery:** If the machine shuts down during FileOptimizer, launch the SAME portable folder on the SAME PC to allow registry recovery before moving the folder to a new PC. If `Data\TraceGuard\registry-recovery.bin` remains and the app reports a restoration failure, do not delete it; inspect the issue.

**Other tools:** Microsoft Sysinternals Process Monitor can trace processes and file/registry operations in real time, but is not included or auto-installed. It requires elevated permissions for detailed captures and is appropriate only as an optional diagnostic.
