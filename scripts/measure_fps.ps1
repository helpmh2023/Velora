# Measures how many frames per second Velora's window actually gets on this PC.
# Runs a short scripted session (about 20 s), then prints the result.
#
#   powershell -File scripts\measure_fps.ps1
#   powershell -File scripts\measure_fps.ps1 -Exe "C:\path\to\velora.exe"
#
# Needs a build that includes the benchmark (any build from 1.0.2 on).
param([string]$Exe = (Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\velora.exe'))

$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$json = Join-Path $env:TEMP 'velora_bench_pacing0.json'
Remove-Item $json -ErrorAction SilentlyContinue

$env:VELORA_BENCH = 'pacing0'
$p = Start-Process $Exe -PassThru
if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'Timed out.' }
if (-not (Test-Path $json)) { throw 'No result file: this build has no benchmark.' }

$d  = Get-Content $json -Raw | ConvertFrom-Json
$ph = $d.phases.pacing_idle
$gap = $ph.gapMs
$verdict = if ($ph.fps -ge 55) { 'smooth' } elseif ($ph.fps -ge 40) { 'OK but below the display rate' } else { 'LOW: frames are not reaching the screen fast enough' }

''
('Frames per second : {0}   -> {1}' -f $ph.fps, $verdict)
('Time between frames (ms): typical {0}, slow end {1}   (a 60 Hz screen would show about 16.7)' -f $gap.p50, $gap.p90)
('Render work per frame   : {0} ms' -f $ph.rasterMs.avg)
''
