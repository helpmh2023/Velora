# Builds native/velora_engine/velora_engine.exe (needs Go: winget install GoLang.Go).
# Pure Go, so cgo is switched off - no C compiler required.
$ErrorActionPreference = 'Stop'
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:CGO_ENABLED = '0'
Push-Location (Join-Path $PSScriptRoot '..\native\velora_engine')
try {
  go build -ldflags '-s -w' -o velora_engine.exe .
  Get-Item velora_engine.exe | Select-Object Name, Length
} finally { Pop-Location }
