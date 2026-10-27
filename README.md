# FileOptimizer True Portable Builder — v1.3 (icon fix)

## What it builds

A **ready-to-run portable application ZIP** for Windows x64, with:

```text
FileOptimizerPortable/
├── FileOptimizerPortable.exe  (native Windows launcher, upstream icon)
├── App/
│   ├── AppInfo/
│   │   ├── appinfo.ini       (PortableApps.com Menu detection)
│   │   ├── appicon.ico       (original embedded vendor icon)
│   │   └── appicon_*.png
│   └── FileOptimizer/
│       ├── FileOptimizer64.exe
│       ├── FileOptimizer32.exe  (if bundled)
│       ├── Plugins64/        (vendor bundle, no cherry-picking)
│       ├── Plugins32/        (if bundled)
│       └── other original vendor files
├── Data/
│   ├── Settings/            (persistent INI options)
│   ├── Logs/                (persistent logs and TraceGuard reports)
│   ├── Temp/                (child-process temp area)
│   ├── Browser/WebView2/    (child-process browser data)
│   └── TraceGuard/          (recoverable detected host state)
├── Other/
│   ├── Source/              (launcher and icon export source)
│   └── BUILD-MANIFEST.txt
└── START-HERE.txt
```

### TraceGuard v1.2 (unchanged in builder v1.3) — what is (and is not) monitored

TraceGuard is integrated into the launcher. You do not have to install a driver, start
PowerShell, or run an external tracking program. On every root-launcher session it takes
**before/after** snapshots of bounded locations: top-level entries in Roaming AppData,
Local AppData, LocalLow, Windows TEMP and FileOptimizer's own App folder, including
subtrees whose name contains `FileOptimizer` or `nikkho`, plus selected
`%USERPROFILE%` FileOptimizer INI/log files. It also compares FileOptimizer's known
HKCU registry namespaces and two FileOptimizer-specific browser-emulation values.
It does **not** audit the whole registry, every subdirectory, or all child-process operations.

The launcher gives a child-process-only `WEBVIEW2_USER_DATA_FOLDER` override
pointing to `Data/Browser/WebView2`, as supported by Microsoft WebView2. FileOptimizer
may also use an older Internet Explorer control, which can create an application-specific
`FEATURE_BROWSER_EMULATION` registry value. TraceGuard snapshots only the two
upstream executable-name values there and restores them after the process exits.
Previous-session registry recovery is attempted automatically after abnormal termination.

TraceGuard automatically **moves newly created folders with exact FileOptimizer-specific
names** found directly beneath monitored roots into `Data/TraceGuard/Recovered`
(never discards their contents). It will not touch existing folders, symlink/reparse
paths, generic Microsoft/Edge/Qt browser caches, or user-selected files elsewhere.
It uses a bounded, SHA-256-verified copy for cross-drive recovery and leaves the
host original untouched if verification fails. Uncertain traces are documented for
review, rather than deleted. Reports are written to `Data/Logs/TraceGuard-*.txt`.
A monitor cannot reliably prove every trace was created by one app from snapshots alone;
for detailed attribution, use Microsoft Sysinternals Process Monitor manually.

**This is not a certified zero-host-traces build.** A Windows runtime test with a full
optimization job is still needed. Logs contain filesystem paths: review before sharing.

### Fix in v1.3 — icon error on FileOptimizer 18.00.2889

The Oct 27, 2026 GitHub Actions failure occurred **after the official archive passed validation and extraction**. The old icon extractor retained a resource-name pointer returned by Windows and used it outside the enumeration callback. Windows may return **numeric** icon IDs or temporary **Unicode string** pointers; reusing a string pointer can make a later `FindResourceW` call fail with `Missing icon resource type 14`.

v1.3 copies icon names during enumeration, handles both numeric and string names, and tries additional vendor icon groups. If the upstream 64-bit executable's icon cannot be recovered, it tries the **original vendor 32-bit binary**, if bundled. It never silently uses the generic Windows application icon. A Windows icon-extraction smoke test now runs before the large SourceForge download. This kit was statically tested; a GitHub Windows runner still needs to validate the updated extractor and completed build.

The executable launcher and TraceGuard v1.2 are intentionally **unchanged**, including the Data folder and cleanup rules. A separate PowerShell final-log formatting issue has also been fixed.

### Correct official source

Use [SourceForge FileOptimizer releases](https://sourceforge.net/projects/nikkhokkho/files/FileOptimizer/) and [maintained source tree](https://sourceforge.net/p/nikkhokkho/code/HEAD/tree/), **not the 2015-era svn2github mirror**. Current confirmed release is `18.00.2889` (Oct 25, 2026). The builder downloads `FileOptimizerFull.7z.exe` (official non-installer), verifies a publisher-listed or manually supplied SHA-256 **when available**; otherwise records its computed SHA-256 and performs official HTTPS, 7-Zip integrity, and package-structure checks (these are NOT equivalent to independent checksum verification); then unpacks it using 7-Zip **without running the self-extractor or installer**. Building the actual Embarcadero C++Builder code is unnecessary and not attempted.

### Steps in GitHub

1. Open your existing `vhick/FileOptimizer-Portable-Builder` repository folder in GitHub Desktop (no need for a new repository).
2. Extract **this v1.3 builder kit** ZIP and copy all files into that local folder, overwriting existing builder files; include the hidden `.github/` folder.
3. In GitHub Desktop, confirm the changed files, enter commit summary `Fix FileOptimizer 18 icon export (v1.3)`, and select **Commit to main** then **Push origin**.
4. Open the repository **Actions** tab; choose **Build FileOptimizer Portable (Manual)**.
5. Click **Run workflow** and use `release_version=18.00.2889` (recommended first test). You may choose `latest` later; if SourceForge version discovery is blocked, the builder uses its last confirmed release as a clearly labeled fallback. The optional `expected_sha256` field is blank by default.
6. When the job succeeds, download the artifact `FileOptimizerPortable-Windows-x64`.
7. Extract the **inner** `FileOptimizerPortable-<version>-x64.zip` to `X:\PortableApps\` (the directory containing `PortableApps.com`).
8. Refresh PortableApps Menu icons and start **FileOptimizer Portable**.

### Updating

**Never overwrite the entire installed portable folder with a fresh extraction.** Close FileOptimizer and ensure optimization is finished; replace `FileOptimizerPortable.exe`, `App/`, and `Other/` only. **Preserve all of `Data/`.** The launcher copies saved INI preferences from Data to the app directory on startup, and copies settings and logs back on exit. It does not touch other application settings.

### Storage and limits

- FileOptimizer officially stores `FileOptimizer.ini` and `FileOptimizer.log` next to its executable when writable; otherwise it may write them to `%USERPROFILE%`. The launcher refuses to start without writable app and Data folders.
- It also handles `FileOptimizer64.ini`, `FileOptimizer32.ini`, and their corresponding `.log` names for compatibility. After an interrupted session it can recover newer staged files in `App/` when restarted. It keeps a `.previous` copy when replacing saved files.
- TEMP and TMP are redirected **only for the launched program and child processes** to `Data/Temp`. Other system processes are unaffected. Plugins may still use their own cache locations; test on Windows.
- Registry overrides at `HKLM/HKCU\Software\FileOptimizer` may affect settings on a PC with a separate installation. The launcher neither modifies nor removes those settings.
- Program output changes the user-selected **original** files. This is intentional functionality, NOT host contamination. Keep original files in the Recycle Bin where supported and first optimize copies.
- No autorun, Explorer shell registration, scheduled job, or background optimization is added by the builder.
- TraceGuard's registry recovery backup is stored in `Data/TraceGuard/registry-recovery.bin` only while a session is active; if an interruption occurs, relaunch on the **same computer** before moving the portable directory. A recovery failure leaves the marker for review.
- Windows itself may record execution history; zero host traces cannot be guaranteed by a launcher.

### Checks and troubleshooting

- **v1.1 fixes SourceForge 403 on the checksum webpage (retained in v1.3).** If a published checksum is accessible, the builder verifies it. The earlier 17.20.2876 pinned hash is retained. A manually supplied `expected_sha256` is always checked against the downloaded file.
- **Important security distinction:** When SourceForge blocks checksum retrieval and no independent expected hash is provided, v1.1 can still build from the official HTTPS release after a 7-Zip archive test, executable/plugin checks and recording the download's calculated SHA-256. This does **not** independently authenticate the archive. The build log and `Other/BUILD-MANIFEST.txt` say `OFFICIAL-HTTPS-UNPINNED` in that case. For a fully hash-verified build, obtain the SHA-256 from the official SourceForge file detail screen and paste it into the optional `expected_sha256` workflow field; mismatches fail immediately.
- Any future version still depends on the upstream archive format. The builder does not run the publisher's self-extracting installer.
- It tests the official archive with `7z t`, then checks the extracted vendor `FileOptimizer64.exe`, `Plugins64/`, official icon, compiled launcher, AppInfo metadata and output ZIP structure.
- If SourceForge changes the archive layout, the build **stops with a specific diagnostic**. It will not silently omit plugins.
- The package is intentionally large (the original 111 MB compressed distribution plus launcher); an artifact near that size is normal.
- No Windows runtime tests were performed here. Verify a complete optimization session, INI persistence, logs, plugins, PortableApps Menu, and Windows traces yourself.

Read [docs/TESTING.md](docs/TESTING.md) before using this build on irreplaceable documents.

This is a community packaging kit, not an official PortableApps.com distribution. The vendor's code and bundled tools retain their respective upstream licenses.

### If the first build was blocked by SourceForge

The October 21, 2026 GitHub Action log reported `403 Forbidden` while fetching a *webpage* containing the checksum; the actual program download had not started. v1.1 separates these steps, retries only official SourceForge download endpoints, and provides an optional strict checksum field. It does not treat an automatically computed hash as publisher verification.
