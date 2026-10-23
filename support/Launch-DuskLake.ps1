# Dusk Lake launcher. Try the built-in Forward+ graphics path first.
# If the engine exits before the first stable rendered frame, retry OpenGL.
# Does not attempt to download GPU drivers or a non-existent Forward+ package.
[CmdletBinding()]
param(
    [switch]$ForceCompatibility,
    [int]$StartupTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here 'DuskLake.exe'
$collector = Join-Path $here 'Collect-DuskLakeCrash.ps1'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host 'DuskLake.exe was not found next to the launcher.'
    exit 2
}
$logDir = Join-Path $env:LOCALAPPDATA 'DuskLake\Diagnostics'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Start-And-Watch([string]$mode, [bool]$compat) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $ready = Join-Path $logDir ('ready-' + $stamp + '.flag')
    $engineLog = Join-Path $logDir ('engine-' + $mode + '-' + $stamp + '.log')
    $stdout = Join-Path $logDir ('stdout-' + $mode + '-' + $stamp + '.log')
    $stderr = Join-Path $logDir ('stderr-' + $mode + '-' + $stamp + '.log')
    $args = @('--verbose', '--log-file', ('"' + $engineLog + '"'))
    if ($compat) {
        $args += @('--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3')
    }
    $args += @('--', '--startup-ready-file', ('"' + $ready + '"'))
    if ($compat) { $args += '--safe-mode' }

    Write-Host ('Dusk Lake: trying ' + $mode)
    try {
        $process = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $here -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -ErrorAction Stop
    } catch {
        ('Start-Process failed: ' + $_.Exception.Message) | Out-File -FilePath (Join-Path $logDir ('launch-' + $mode + '-' + $stamp + '.txt'))
        return @{ Ready = $false; Exited = $true; Code = 'start_failed' }
    }

    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $ready) {
            Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
            Write-Host ('Dusk Lake: ' + $mode + ' rendered and is running (PID ' + $process.Id + ')')
            return @{ Ready = $true; Exited = $false; Code = 0 }
        }
        $process.Refresh()
        if ($process.HasExited) {
            Start-Sleep -Milliseconds 300
            if (Test-Path -LiteralPath $ready) {
                Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
                return @{ Ready = $true; Exited = $true; Code = $process.ExitCode }
            }
            Write-Host ('Dusk Lake: ' + $mode + ' exited during startup, code ' + $process.ExitCode)
            return @{ Ready = $false; Exited = $true; Code = $process.ExitCode }
        }
        Start-Sleep -Milliseconds 350
    }
    # A slowly loading machine may exceed 60s: never start a second copy
    # while the first process is alive.
    Write-Host ('Dusk Lake: timed out waiting for startup confirmation (PID ' + $process.Id + ' still alive).')
    return @{ Ready = $false; Exited = $false; Code = 'timeout' }
}

$tries = @()
if ($ForceCompatibility) {
    $tries += @{ Mode = 'compatibility'; Compat = $true }
} else {
    $tries += @{ Mode = 'forward-plus-auto'; Compat = $false }
    $tries += @{ Mode = 'compatibility'; Compat = $true }
}
foreach ($try in $tries) {
    $result = Start-And-Watch $try.Mode $try.Compat
    if ($result.Ready) { exit 0 }
    if (-not $result.Exited) {
        Write-Host 'Game is still running. Skipping fallback to avoid two copies.'
        exit 0
    }
}
Write-Host 'Both rendering paths failed. Collecting a local crash report.'
if (Test-Path -LiteralPath $collector) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -NoLaunch -GameExe $exe
}
exit 1
