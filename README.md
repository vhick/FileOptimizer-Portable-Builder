# FileOptimizer True Portable Builder — v1.1

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
│   ├── Logs/                (persistent logs)
│   └── Temp/                (child-process temp area)
├── Other/
│   ├── Source/              (launcher and icon export source)
│   └── BUILD-MANIFEST.txt
└── START-HERE.txt
```

### Correct official source

Use [SourceForge FileOptimizer releases](https://sourceforge.net/projects/nikkhokkho/files/FileOptimizer/) and [maintained source tree](https://sourceforge.net/p/nikkhokkho/code/HEAD/tree/), **not the 2015-era svn2github mirror**. Current confirmed release is `17.30.2881` (Oct 20, 2026). The builder downloads `FileOptimizerFull.7z.exe` (official non-installer), verifies a publisher-listed or manually supplied SHA-256 **when available**; otherwise records its computed SHA-256 and performs official HTTPS, 7-Zip integrity, and package-structure checks (these are NOT equivalent to independent checksum verification); then unpacks it using 7-Zip **without running the self-extractor or installer**. Building the actual Embarcadero C++Builder code is unnecessary and not attempted.

### Steps in GitHub

1. Create a repository, e.g. `FileOptimizer-Portable-Builder`.
2. Extract **this builder kit** ZIP and copy all contents into the repository. Include the `.github/` folder.
3. Commit and push in GitHub Desktop.
4. Open the repository **Actions** tab; choose **Build FileOptimizer Portable (Manual)**.
5. Click **Run workflow** and use `release_version=17.30.2881` (recommended first test). You may choose `latest` later; if SourceForge version discovery is blocked, the builder uses its last confirmed release as a clearly labeled fallback. The optional `expected_sha256` field is blank by default.
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
- Windows itself may record execution history; zero host traces cannot be guaranteed by a launcher.

### Checks and troubleshooting

- **v1.1 fixes SourceForge 403 on the checksum webpage.** If a published checksum is accessible, the builder verifies it. The earlier 17.20.2876 pinned hash is retained. A manually supplied `expected_sha256` is always checked against the downloaded file.
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
