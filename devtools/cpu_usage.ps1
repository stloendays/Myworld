# 测游戏在几个机位上的真实 CPU 占用（配合 devtools/CpuSpots.tscn）。
#   pwsh -File devtools/cpu_usage.ps1 [-Label 改前] [-Godot <console exe>] [-Resolution 1600x900]
# 输出每个机位的平均 CPU 占用（100% = 一个逻辑核满载）和全部逻辑核的百分比，结果也追加到 devtools/cpu_usage.log（本机记录，不进仓库）。
param(
	[string]$Label = "",
	[string]$Godot = "D:\个人世界\tools\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe",
	[string]$Resolution = "1600x900"
)
$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$log = Join-Path $env:TEMP ("dusk_cpu_" + [guid]::NewGuid().ToString("N") + ".log")
$cores = [Environment]::ProcessorCount
$p = Start-Process -FilePath $Godot -ArgumentList @("--path", "`"$project`"", "--resolution", $Resolution, "--position", "100000,100000", "res://devtools/CpuSpots.tscn") `
	-RedirectStandardOutput $log -PassThru -WindowStyle Hidden
# _console.exe 只是个外壳，真正的游戏是它启动的子进程：量子进程
$gameId = 0
for ($i = 0; $i -lt 40 -and $gameId -eq 0; $i++) {
	Start-Sleep -Milliseconds 250
	$child = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($p.Id)" | Where-Object { $_.Name -like "Godot*" } | Select-Object -First 1
	if ($child) { $gameId = $child.ProcessId }
}
$samples = New-Object System.Collections.Generic.List[object]
while (-not $p.HasExited) {
	try {
		# 进程 CPU 时间走 WMI（Get-Process 在这里读不到别的进程的 CPU 时间），单位 100 ns
		$w = Get-CimInstance Win32_Process -Filter "ProcessId = $gameId"
		if ($w) {
			$samples.Add([pscustomobject]@{ t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); cpu = ([double]$w.KernelModeTime + [double]$w.UserModeTime) / 10000.0 })
		}
	} catch {}
	Start-Sleep -Milliseconds 500
}
$lines = Get-Content $log -Encoding UTF8 | Where-Object { $_ -like "CPUSPOT*" }
$starts = @{}
$out = @()
foreach ($l in $lines) {
	$parts = $l -split " "
	if ($parts[1] -eq "开始") { $starts[$parts[2]] = [int64]$parts[3] }
	elseif ($parts[1] -eq "结束") {
		$name = $parts[2]; $t0 = $starts[$name]; $t1 = [int64]$parts[3]
		$win = $samples | Where-Object { $_.t -ge $t0 -and $_.t -le $t1 }
		if ($win.Count -ge 2) {
			$a = $win[0]; $b = $win[$win.Count - 1]
			$pct = ($b.cpu - $a.cpu) / ($b.t - $a.t) * 100.0
			$out += ("CPU {0,-8} {1,6:N1} % 单核  ({2:N1} % 全部 {3} 核)" -f $name, $pct, ($pct / $cores), $cores)
		}
	} else { $out += $l }
}
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$load = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$header = "=== $stamp $Label（结束时系统负载 $load %）==="
$header; $out
Add-Content -Path (Join-Path $PSScriptRoot "cpu_usage.log") -Value (@($header) + $out) -Encoding UTF8
Remove-Item $log -ErrorAction SilentlyContinue
