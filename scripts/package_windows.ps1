# Builds the Windows release and packages it:
#   dist\Velora-<version>-windows-x64\          the app folder (run velora.exe)
#   dist\Velora-<version>-windows-x64.zip       portable zip
#   dist\Velora-Setup-<version>.exe             installer (only if Inno Setup is installed)
#
#   powershell -File scripts\package_windows.ps1            # full build + package
#   powershell -File scripts\package_windows.ps1 -SkipBuild # repackage the last build
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

# Version from pubspec.yaml ("1.0.0+1" -> "1.0.0")
$ver = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]
Write-Host "Velora $ver" -ForegroundColor Cyan

if (-not $SkipBuild) {
    & "$PSScriptRoot\build_engine.ps1"
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'velora.exe'))) { throw "No release build at $release" }
if (-not (Test-Path (Join-Path $release 'velora_engine.exe'))) { throw 'velora_engine.exe is missing from the build' }

$dist  = Join-Path $root 'dist'
$name  = "Velora-$ver-windows-x64"
$stage = Join-Path $dist $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $release '*') $stage -Recurse

# Visual C++ runtime, app-local, so the app starts on a PC that has never
# installed the "VC++ Redistributable". (These DLLs are redistributable.)
$crt = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
    if (Test-Path (Join-Path $stage $dll)) { continue }
    $src = if ($crt) { Join-Path $crt.FullName $dll } else { $null }
    if ($src -and (Test-Path $src)) { Copy-Item $src $stage }
    else { Write-Warning "$dll not bundled (Visual C++ runtime not found)" }
}

# Portable zip
$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host ("Portable zip : {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB)) -ForegroundColor Green

# Installer (needs Inno Setup 6: winget install JRSoftware.InnoSetup)
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue; if ($cmd) { $iscc = $cmd.Source } }

if ($iscc) {
    & $iscc "/DAppVersion=$ver" "/DSourceDir=$stage" (Join-Path $root 'installer\velora.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
    $setup = Join-Path $dist "Velora-Setup-$ver.exe"
    Write-Host ("Installer    : {0} ({1:N1} MB)" -f $setup, ((Get-Item $setup).Length / 1MB)) -ForegroundColor Green
} else {
    Write-Warning 'Inno Setup not found - skipped the installer. Install it with: winget install JRSoftware.InnoSetup'
}
