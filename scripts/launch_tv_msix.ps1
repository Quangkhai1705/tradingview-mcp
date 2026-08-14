# Launch TradingView Desktop (Windows MSIX / Microsoft Store install) with CDP enabled.
#
# Why this exists: on MSIX installs the two paths the repo already tries both fail.
#   1. spawn() straight from C:\Program Files\WindowsApps\...  -> EPERM / "Access is denied"
#   2. copying the package out to LOCALAPPDATA and running it  -> starts, then exits
#      immediately (the app loses its MSIX package identity)
# Invoke-CommandInDesktopPackage runs the real exe INSIDE the package context, so identity
# is preserved AND the --remote-debugging-port flag is passed through.
# Measured working: Windows 10 19045, TradingView.Desktop 3.3.0.7992, 2026-08-14.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\launch_tv_msix.ps1 [port]

param([int]$Port = 9222)

$ErrorActionPreference = 'Stop'

$pkg = Get-AppxPackage -Name 'TradingView.Desktop' -ErrorAction SilentlyContinue
if (-not $pkg) { Write-Error 'TradingView.Desktop MSIX package not found (is it a Store install?)'; exit 1 }

[xml]$manifest = Get-Content (Join-Path $pkg.InstallLocation 'AppxManifest.xml')
$appId = @($manifest.Package.Applications.Application)[0].Id
$exe = Join-Path $pkg.InstallLocation 'TradingView.exe'

Write-Output "package : $($pkg.PackageFamilyName)"
Write-Output "appId   : $appId"
Write-Output "exe     : $exe"

# CDP only binds on a fresh process; an already-running instance would just take focus.
Get-Process -Name 'TradingView*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Invoke-CommandInDesktopPackage -PackageFamilyName $pkg.PackageFamilyName -AppId $appId `
    -Command $exe -Args "--remote-debugging-port=$Port"

Write-Output "waiting for CDP on 127.0.0.1:$Port ..."
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/version" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Write-Output "CDP ready after $($i * 2)s"
        Write-Output $r.Content
        exit 0
    } catch { }
}

Write-Error "CDP never bound on port $Port after 60s"
exit 1
