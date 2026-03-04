# ============================================================
# Uninstaller - Claude Clipboard Bridge
# ============================================================
# Double-click uninstall.bat, or run from PowerShell:
#   powershell -ExecutionPolicy Bypass -NoProfile -File uninstall.ps1
# ============================================================

$taskName = "ClaudeClipboardBridge"

Write-Host ""
Write-Host "  Claude Clipboard Bridge - Uninstaller" -ForegroundColor Cyan
Write-Host "  ======================================" -ForegroundColor Cyan
Write-Host ""

# Stop scheduled task first (prevents restart)
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# Stop running instances using CimInstance (works on PS 5.1)
$procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'powershell%' OR Name LIKE 'pwsh%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*claude-clipboard-bridge*" -and $_.ProcessId -ne $PID }

if ($procs -and @($procs).Count -gt 0) {
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] Stopped $(@($procs).Count) running instance(s)" -ForegroundColor Green
} else {
    Write-Host "  [--] No running instances found" -ForegroundColor Gray
}

# Remove scheduled task
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "  [OK] Removed auto-start task" -ForegroundColor Green
} else {
    Write-Host "  [--] No auto-start task found" -ForegroundColor Gray
}

# Remove Start Menu shortcut
$shortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Claude Clipboard Bridge.lnk"
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "  [OK] Removed Start Menu shortcut" -ForegroundColor Green
} else {
    Write-Host "  [--] No Start Menu shortcut found" -ForegroundColor Gray
}

# Offer to remove install directory (remote install)
$remoteInstallDir = Join-Path $env:LOCALAPPDATA "claude-clipboard-bridge"
if ((Test-Path $remoteInstallDir) -and $remoteInstallDir -ne $PSScriptRoot) {
    $confirm = Read-Host "  Delete program files in $remoteInstallDir? (y/N)"
    if ($confirm -eq 'y') {
        Remove-Item $remoteInstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed program files" -ForegroundColor Green
    } else {
        Write-Host "  [--] Program files kept" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  Uninstall complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NOTE: Screenshots in C:\tmp\claude-clipboard were kept." -ForegroundColor Yellow
Write-Host "  Delete that folder manually if you don't need them." -ForegroundColor Yellow
Write-Host ""

Read-Host "Press Enter to close"
