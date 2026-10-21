param([string]$ReleaseVersion = 'latest')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
if ($ReleaseVersion -ne 'latest' -and $ReleaseVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw 'release_version must be latest or an official three-part version such as 17.20.2876.'
}
$headers = @{ 'User-Agent'='FileOptimizer-Portable-Community-Builder/1.0' }
function Resolve-ReleaseVersion {
    param([string]$Requested)
    if ($Requested -ne 'latest') { return $Requested }
    # SourceForge is the upstream release source; avoid the stale svn2github mirror.
    # Try the SourceForge folder listing, then the SourceForge RSS feed.
    $versions = New-Object System.Collections.Generic.List[string]
    $folderUrl = 'https://sourceforge.net/projects/nikkhokkho/files/FileOptimizer/'
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $folderUrl -Headers $headers -TimeoutSec 60
        foreach($m in [regex]::Matches($resp.Content, '/FileOptimizer/(\d+\.\d+\.\d+)/')) {
            $versions.Add($m.Groups[1].Value)
        }
    } catch { Write-Warning ('SourceForge directory lookup failed: ' + $_.Exception.Message) }
    if ($versions.Count -eq 0) {
        try {
            $rss = Invoke-WebRequest -UseBasicParsing -Uri 'https://sourceforge.net/projects/nikkhokkho/rss?path=/FileOptimizer' -Headers $headers -TimeoutSec 60
            foreach($m in [regex]::Matches($rss.Content, '/FileOptimizer/(\d+\.\d+\.\d+)/')) {
                $versions.Add($m.Groups[1].Value)
            }
        } catch { Write-Warning ('SourceForge RSS lookup failed: ' + $_.Exception.Message) }
    }
    if ($versions.Count -eq 0) { throw 'Cannot determine latest official version from SourceForge. Retry with release_version=17.20.2876 (or a confirmed newer version).' }
    $sorted = @($versions | Sort-Object -Unique | Sort-Object { [version]$_ } -Descending)
    return [string]$sorted[0]
}
$version = Resolve-ReleaseVersion -Requested $ReleaseVersion
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Unrecognized upstream version.' }
Write-Host "Selected upstream official FileOptimizer $version"
$asset = 'FileOptimizerFull.7z.exe'
$downloadUrl = "https://downloads.sourceforge.net/project/nikkhokkho/FileOptimizer/$version/$asset"
$sourcePage = "https://sourceforge.net/projects/nikkhokkho/files/FileOptimizer/$version/$asset/download"
# Upstream-published SHA256 for initial version, grounded in official SourceForge file page.
# For newer versions require a SHA256 from that version's SourceForge file page.
$knownHashes = @{ '17.20.2876' = '9f0a3aef27adece2ab3cedbb004c084ad9e1a36f79155dd3e0e2d7fc0182fb72' }
$expected = $null
try {
    $fileInfo = Invoke-WebRequest -UseBasicParsing -Uri $sourcePage -Headers @{ 'User-Agent' = 'Mozilla/5.0 FileOptimizer-Portable-Builder' } -TimeoutSec 45
    $asText = [string]$fileInfo.Content
    $match = [regex]::Match($asText, '(?is)SHA-256:[\s\S]{0,500}?([a-fA-F0-9]{64})')
    if ($match.Success) { $expected = $match.Groups[1].Value.ToLowerInvariant() }
} catch { Write-Warning ('Unable to read published SourceForge checksum: ' + $_.Exception.Message) }
if ($knownHashes.ContainsKey($version)) {
    if ($expected -and $expected -ne $knownHashes[$version]) { throw 'Upstream checksum differs from pinned expected checksum.' }
    $expected = $knownHashes[$version]
}
if (-not $expected) { throw "No published SourceForge SHA256 could be verified for $version. Builder will not package an unverified download." }
$work = Join-Path $repoRoot 'build-work'
$dist = Join-Path $repoRoot 'dist'
$stage = Join-Path $work 'FileOptimizerPortable'
$app = Join-Path $stage 'App/FileOptimizer'
$appInfo = Join-Path $stage 'App/AppInfo'
$data = Join-Path $stage 'Data'
$srcDir = Join-Path $stage 'Other/Source'
if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
if (Test-Path $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work,$stage,$app,$appInfo,$data,$srcDir,$dist, (Join-Path $data 'Settings'),(Join-Path $data 'Logs'),(Join-Path $data 'Temp') | Out-Null
$archive = Join-Path $work $asset
Write-Host "Downloading $downloadUrl"
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -Headers $headers -OutFile $archive -TimeoutSec 1800
if ((Get-Item -LiteralPath $archive).Length -lt 40000000) { throw 'Official full distribution is unexpectedly small (or HTML download error).' }
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Official SHA-256 mismatch! Expected $expected, actual $actual" }
Write-Host "PASS: Official upstream SHA-256 $actual"
# Extract SFX as archive; do NOT execute the vendor SFX on the GitHub runner.
$seven = @('C:\Program Files\7-Zip\7z.exe','C:\Program Files (x86)\7-Zip\7z.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $seven) { $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue; if ($cmd) { $seven = $cmd.Source } }
if (-not $seven) { throw '7-Zip CLI is missing on Windows runner. Do not execute the vendor SFX as an installer.' }
$extracted = Join-Path $work 'extracted'
New-Item -ItemType Directory -Force -Path $extracted | Out-Null
& $seven x '-y' '-bd' "-o$extracted" $archive
if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed ($LASTEXITCODE)." }
$entry = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter FileOptimizer64.exe)
if ($entry.Count -ne 1) {
    $found = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter '*Optimizer*.exe' | Select-Object -ExpandProperty FullName)
    throw "Expected exactly one FileOptimizer64.exe; found $($entry.Count). Candidates: $($found -join '; ')"
}
# The full upstream bundle must include the optimization plugins in the executable's directory.
$programRoot = $entry[0].DirectoryName
if (-not (Test-Path (Join-Path $programRoot 'Plugins64'))) {
    $dirs = @(Get-ChildItem -LiteralPath $extracted -Recurse -Directory -Filter Plugins64 | Select-Object -ExpandProperty FullName)
    throw "Official Plugins64 directory missing beside vendor EXE. Found: $($dirs -join '; '). Inspect upstream layout before changing packaging."
}
Get-ChildItem -LiteralPath $programRoot -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $app -Recurse -Force }
foreach ($required in @('FileOptimizer64.exe','Plugins64')) {
    if (-not (Test-Path (Join-Path $app $required))) { throw "Staging lost official component: $required" }
}
if (@(Get-ChildItem -LiteralPath (Join-Path $app 'Plugins64') -Recurse -File).Count -lt 15) {
    throw 'Plugins64 unexpectedly contains fewer than 15 plugin files.'
}
# Move any vendor-included INIs/logs into persistent Data; no stale settings in replaceable App/.
foreach($name in @('FileOptimizer.ini','FileOptimizer64.ini','FileOptimizer32.ini','FileOptimizer.log','FileOptimizer64.log','FileOptimizer32.log')) {
    $p = Join-Path $app $name
    if (Test-Path -LiteralPath $p) {
        $sub = if ($name.EndsWith('.log')) { 'Logs' } else { 'Settings' }
        Move-Item -LiteralPath $p -Destination (Join-Path $data $sub) -Force
    }
}
# Preserve exact original embedded multi-resolution icon from the current official binary.
$icon = Join-Path $appInfo 'appicon.ico'
& (Join-Path $PSScriptRoot 'Extract-OfficialIcon.ps1') -ExePath (Join-Path $app 'FileOptimizer64.exe') -OutputPath $icon
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw 'Windows .NET Framework C# compiler not found.' }
$launcher = Join-Path $stage 'FileOptimizerPortable.exe'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$launcher" "/win32icon:$icon" /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll /reference:System.Security.dll (Join-Path $repoRoot 'launcher/FileOptimizerPortable.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $launcher)) { throw 'Compiling the native root launcher failed.' }
Add-Type -AssemblyName System.Drawing
foreach($size in @(16,32,75,128,256)) {
    $imagePath = Join-Path $appInfo "appicon_$size.png"
    $ico = New-Object System.Drawing.Icon($icon, $size, $size)
    try {
        $bitmap = $ico.ToBitmap()
        try {
            $scaled = New-Object System.Drawing.Bitmap($bitmap, $size, $size)
            try { $scaled.Save($imagePath, [System.Drawing.Imaging.ImageFormat]::Png) }
            finally { $scaled.Dispose() }
        } finally { $bitmap.Dispose() }
    } finally { $ico.Dispose() }
    if ((Get-Item -LiteralPath $imagePath).Length -lt 100) { throw "Icon PNG invalid: $imagePath" }
}
$parts = $version.Split('.')
$fourPart = "$($parts[0]).$($parts[1]).$($parts[2]).0"
@"
[Format]
Type=PortableApps.comFormat
Version=3.9

[Details]
Name=FileOptimizer Portable
AppID=FileOptimizerPortable-Community
Publisher=Javier Gutierrez Chamorro (original developer)
Homepage=https://sourceforge.net/projects/nikkhokkho/
Category=Utilities
Description=File size optimization with a community portable launcher
Language=Multilingual

[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true

[Version]
PackageVersion=$fourPart
DisplayVersion=$version

[Control]
Icons=1
Start=FileOptimizerPortable.exe
"@ | Set-Content -LiteralPath (Join-Path $appInfo 'appinfo.ini') -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $repoRoot 'launcher/FileOptimizerPortable.cs') -Destination $srcDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Extract-OfficialIcon.ps1') -Destination $srcDir
@"
FileOptimizer portable build
Official upstream: $downloadUrl
Official upstream SHA256: $expected
Release version: $version
Source code (maintained): https://sourceforge.net/p/nikkhokkho/code/HEAD/tree/
Build approach: official precompiled SFX extracted as an archive; neither installed nor executed on runner.
Root launcher: .NET Framework 4.8 Windows executable with original embedded icon.
Original application: unmodified FileOptimizer64.exe and all adjacent plugins.
"@ | Set-Content -LiteralPath (Join-Path $stage 'Other/BUILD-MANIFEST.txt') -Encoding UTF8
@'
START HERE - FileOptimizer Portable

Install: Extract the INNER ZIP directly into X:\PortableApps\.
You should have X:\PortableApps\FileOptimizerPortable\FileOptimizerPortable.exe
Refresh icons in PortableApps Menu; look for FileOptimizer Portable.

Always start FileOptimizerPortable.exe from the root folder.
It stores the INI and logs in Data\Settings and Data\Logs after exiting,
and points the optimizer's temporary child-process environment into Data\Temp.
For upgrades replace only root launcher, App, Other. KEEP Data.

SAFETY: This program optimizes/replaces the files YOU choose. It can modify
recompress images, archives and documents, affecting later editability and metadata.
First test on copies of important files. Keep original files in Recycle Bin
(DoNotUseRecycleBin=false) where supported. Do not optimize portable programs,
software installation folders, personal archives, or backups without spare copies.
Disable optional shell/context-menu registration to avoid host changes.

LIMITS: FileOptimizer can read existing registry overrides; it normally doesn't
write its own registry options. Third-party plugin components may make Windows
caches/traces outside Data. Zero-remnant behavior needs an actual PC audit.
Do not start App\FileOptimizer\FileOptimizer64.exe directly: settings isolation
then bypasses the launcher. Do not run portable build and installed copy together.
'@ | Set-Content -LiteralPath (Join-Path $stage 'START-HERE.txt') -Encoding UTF8
& $launcher --self-test
if ($LASTEXITCODE -ne 0) { throw "Launcher self-test failed: $LASTEXITCODE" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dist "FileOptimizerPortable-$version-x64.zip"
# Package ONLY the complete portable folder; never include downloads or extraction work.
$packRoot = Join-Path $work 'portable-only'
New-Item -ItemType Directory -Force -Path $packRoot | Out-Null
Move-Item -LiteralPath $stage -Destination $packRoot
[System.IO.Compression.ZipFile]::CreateFromDirectory($packRoot, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Add-Type -AssemblyName System.IO.Compression
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    foreach($required in @('FileOptimizerPortable/FileOptimizerPortable.exe','FileOptimizerPortable/App/AppInfo/appinfo.ini','FileOptimizerPortable/App/AppInfo/appicon.ico','FileOptimizerPortable/App/FileOptimizer/FileOptimizer64.exe')) {
        if ($names -notcontains $required) { throw "Final ZIP missing $required" }
    }
} finally { $z.Dispose() }
Write-Host "SUCCESS: $zip"
Write-Host 'Windows GUI and full plugin portability must still be tested on the target PC.'
