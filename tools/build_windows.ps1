#requires -Version 5.1
# Dusk Lake deterministic Windows export builder.
# Downloads official Godot 4.7.2 editor and export template only if missing.
# Forward+ ships inside the game; end users need a compatible GPU driver.
[CmdletBinding()]
param([switch]$SkipEngineTests)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$version = '4.7.2'
$tag = $version + '-stable'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$toolchain = Join-Path $root '.godot-toolchain'
$editor = Join-Path $toolchain 'editor'
$baseUrl = 'https://github.com/godotengine/godot/releases/download/' + $tag + '/'
$editorZip = Join-Path $toolchain ('Godot_v' + $tag + '_win64.exe.zip')
$templateZip = Join-Path $toolchain ('Godot_v' + $tag + '_export_templates.tpz')
$template = Join-Path $toolchain 'windows_release_x86_64.exe'
$cache = Join-Path $toolchain ('Godot_v' + $tag + '_win64_console.exe')
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $toolchain,$editor,$dist -Force | Out-Null

function Invoke-Download([string]$url, [string]$out) {
    Write-Host ('Downloading ' + $url)
    & curl.exe --fail --location --retry 4 --retry-delay 5 --output $out $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        throw ('Download failed: ' + $url)
    }
}
if (-not (Test-Path -LiteralPath $cache)) {
    if (-not (Test-Path -LiteralPath $editorZip)) {
        Invoke-Download ($baseUrl + ('Godot_v' + $tag + '_win64.exe.zip')) $editorZip
    }
    Expand-Archive -LiteralPath $editorZip -DestinationPath $editor -Force
    $console = Get-ChildItem -LiteralPath $editor -Recurse -File |
        Where-Object { $_.Name -eq ('Godot_v' + $tag + '_win64_console.exe') } |
        Select-Object -First 1
    if ($null -eq $console) { throw 'Godot console executable not found in editor archive.' }
    Copy-Item -LiteralPath $console.FullName -Destination $cache -Force
    $guiName = 'Godot_v' + $tag + '_win64.exe'
    $gui = Get-ChildItem -LiteralPath $editor -Recurse -File |
        Where-Object { $_.Name -eq $guiName } | Select-Object -First 1
    if ($null -eq $gui) { throw 'Godot GUI executable missing next to console wrapper.' }
    Copy-Item -LiteralPath $gui.FullName -Destination (Join-Path $toolchain $guiName) -Force
}
if (-not (Test-Path -LiteralPath $template)) {
    if (-not (Test-Path -LiteralPath $templateZip)) {
        Invoke-Download ($baseUrl + ('Godot_v' + $tag + '_export_templates.tpz')) $templateZip
    }
    Write-Host 'Extracting Windows x86_64 template from the official TPZ archive.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tpz = [System.IO.Compression.ZipFile]::OpenRead($templateZip)
    try {
        $entry = $tpz.Entries |
            Where-Object { $_.Name -eq 'windows_release_x86_64.exe' } |
            Select-Object -First 1
        if ($null -eq $entry) {
            throw 'Official export archive has no windows_release_x86_64.exe.'
        }
        Write-Host ('Template inside archive: ' + $entry.FullName)
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $template, $true)
    } finally {
        $tpz.Dispose()
    }
    if (-not (Test-Path -LiteralPath $template)) {
        throw 'Official Windows release export template extraction failed.'
    }
}
$installed = Join-Path $env:APPDATA ('Godot\export_templates\' + $version + '.stable')
New-Item -ItemType Directory -Path $installed -Force | Out-Null
Copy-Item -LiteralPath $template -Destination (Join-Path $installed 'windows_release_x86_64.exe') -Force
$godot = $cache
Write-Host ('Godot: ' + $godot)
& $godot --headless --version
if ($LASTEXITCODE -ne 0) { throw 'Failed to run the Godot editor.' }
if (-not $SkipEngineTests) {
    Write-Host 'Importing project assets.'
    & $godot --headless --path $root --import
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }

    Write-Host 'Running game test suite.'
    & $godot --headless --path $root --fixed-fps 60 'res://tests/TestRunner.tscn'
    if ($LASTEXITCODE -ne 0) { throw 'Game tests failed.' }
}
Write-Host 'Exporting an x64 single-file Windows EXE.'
$exe = Join-Path $dist 'DuskLake.exe'
if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }
& $godot --headless --path $root --export-release 'Windows Desktop' $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
    throw 'Godot release export failed.'
}
if ((Get-Item -LiteralPath $exe).Length -lt 50000000) {
    throw 'Suspiciously small EXE: expected packed assets.'
}
Write-Host 'Smoke-testing EXPORTED Windows EXE without graphics.'
$smoke = Join-Path $dist 'export-smoke.log'
$smokeTxt = Join-Path $dist 'export-smoke-stdout.txt'
& $exe --headless --log-file $smoke --quit-after 90 -- --safe-mode --skip-menu 2>&1 |
    Out-File -FilePath $smokeTxt -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw ('Exported EXE smoke test exited ' + $LASTEXITCODE) }
if (Test-Path -LiteralPath $smoke) {
    $log = Get-Content -LiteralPath $smoke -Raw
    if ($log -match 'SCRIPT ERROR:|Parse Error:|Failed loading resource:') {
        throw 'Exported EXE reported a script/resource loading error.'
    }
}
Write-Host 'Packaging launcher and diagnostics alongside the actual EXE.'
$portable = Join-Path $dist 'DuskLake-Portable'
New-Item -ItemType Directory -Path $portable -Force | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $portable 'DuskLake.exe') -Force
Get-ChildItem -LiteralPath (Join-Path $root 'support') -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $portable -Force }
$archive = Join-Path $dist 'DuskLake-Portable-v0.3.4-rc.1.zip'
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
Compress-Archive -Path (Join-Path $portable '*') -DestinationPath $archive -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
($hash + '  DuskLake.exe') | Out-File -LiteralPath (Join-Path $dist 'DuskLake.exe.sha256') -Encoding ascii
Write-Host ('EXE SHA256: ' + $hash)
Write-Host ('Portable package: ' + $archive)
if ($env:GITHUB_STEP_SUMMARY) {
    ("Godot " + $version + " | EXE SHA256: " + $hash) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
