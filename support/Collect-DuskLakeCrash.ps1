# Collect a local report on Windows 10/11. Never uploads data.
[CmdletBinding()]
param(
    [ValidateSet('default','opengl')]
    [string]$Mode = 'default',
    [string]$GameExe = '',
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GameExe)) { $GameExe = Join-Path $here 'DuskLake.exe' }
try { $exe = (Resolve-Path -LiteralPath $GameExe -ErrorAction Stop).Path } catch {
    Write-Host 'DuskLake.exe was not found.'; exit 2
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop = $env:TEMP }
$dir = Join-Path $desktop ('DuskLake-Diagnostics-' + $stamp + '-' + $Mode)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$info = Join-Path $dir 'system.txt'
('Diagnostic mode: ' + $Mode) | Out-File -LiteralPath $info -Encoding UTF8
('Generated: ' + (Get-Date -Format o)) | Out-File -LiteralPath $info -Append -Encoding UTF8
('Game EXE: ' + $exe) | Out-File -LiteralPath $info -Append -Encoding UTF8
('Privacy: review usernames and file paths before sharing.') | Out-File -LiteralPath $info -Append -Encoding UTF8
try {
    Get-FileHash -LiteralPath $exe -Algorithm SHA256 | Format-List | Out-File -LiteralPath $info -Append -Encoding UTF8
} catch {}
try {
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture |
        Format-List | Out-File -LiteralPath $info -Append -Encoding UTF8
} catch {}
try {
    Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM,VideoProcessor |
        Format-List | Out-File -LiteralPath $info -Append -Encoding UTF8
} catch {}

$started = Get-Date
if (-not $NoLaunch) {
    $engine = Join-Path $dir 'godot-run.log'
    $stdout = Join-Path $dir 'stdout.txt'
    $stderr = Join-Path $dir 'stderr.txt'
    $arguments = @('--verbose', '--log-file', ('"' + $engine + '"'), '--', '--safe-mode')
    if ($Mode -eq 'opengl') {
        $arguments = @('--verbose', '--log-file', ('"' + $engine + '"'),
            '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3',
            '--', '--safe-mode')
    }
    Write-Host 'Starting Dusk Lake. Close the game to finish the report.'
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $exe) -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        ('Game exit code: ' + $p.ExitCode) | Out-File -LiteralPath $info -Append -Encoding UTF8
    } catch {
        $_ | Out-String | Out-File -LiteralPath (Join-Path $dir 'launch-error.txt') -Encoding UTF8
    }
}
$folders = @(
    (Join-Path $env:LOCALAPPDATA 'DuskLake\Diagnostics'),
    (Join-Path $env:APPDATA 'DuskLake\logs'),
    (Join-Path $env:APPDATA 'DuskLake\diagnostics'),
    (Join-Path $env:APPDATA 'Godot\app_userdata\DuskLake\logs'),
    (Join-Path $env:APPDATA 'Godot\app_userdata\DuskLake\diagnostics')
)
for ($i = 0; $i -lt $folders.Count; $i++) {
    if (Test-Path -LiteralPath $folders[$i]) {
        $copy = Join-Path $dir ('logs-' + $i)
        New-Item -ItemType Directory -Force -Path $copy | Out-Null
        Get-ChildItem -LiteralPath $folders[$i] -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 12 |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $copy -ErrorAction SilentlyContinue }
    }
}
try {
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$started.AddHours(-4)} -ErrorAction Stop |
        Where-Object { $_.Id -in @(1000,1001,1002,1026) -and $_.Message -match 'DuskLake|godot' } |
        Select-Object -First 30 TimeCreated,Id,ProviderName,Message | Format-List |
        Out-File -LiteralPath (Join-Path $dir 'windows-events.txt') -Encoding UTF8 -Width 250
} catch {
    ('Cannot read event log: ' + $_.Exception.Message) |
        Out-File -LiteralPath (Join-Path $dir 'windows-events.txt') -Encoding UTF8
}
$zip = $dir + '.zip'
try {
    Compress-Archive -LiteralPath $dir -DestinationPath $zip -CompressionLevel Optimal -Force
    Write-Host ('Report created: ' + $zip)
} catch {
    Write-Host ('Report folder created: ' + $dir)
}
Write-Host 'Nothing uploaded. Review private file paths before sharing.'
