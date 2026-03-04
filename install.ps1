# ============================================================
# Installer - Claude Clipboard Bridge
# ============================================================
# Double-click install.bat, or run from PowerShell:
#   powershell -ExecutionPolicy Bypass -NoProfile -File install.ps1
# ============================================================

$ErrorActionPreference = "Stop"

if (-not $PSScriptRoot) {
    Write-Host "ERROR: This script must be run as a file, not piped." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$scriptDir = $PSScriptRoot
$scriptPath = Join-Path $scriptDir "claude-clipboard-bridge.ps1"
$taskName = "ClaudeClipboardBridge"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: claude-clipboard-bridge.ps1 not found!" -ForegroundColor Red
    Write-Host "Make sure all files are in the same folder." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "  Claude Clipboard Bridge - Installer" -ForegroundColor Cyan
Write-Host "  ====================================" -ForegroundColor Cyan
Write-Host ""

# Create save directory
$saveDir = "C:\tmp\claude-clipboard"
try {
    if (-not (Test-Path $saveDir)) {
        New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
        Write-Host "  [OK] Created screenshot folder: $saveDir" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Screenshot folder exists: $saveDir" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Cannot create $saveDir - check permissions" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Kill any existing bridge process
$existingProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'powershell%' OR Name LIKE 'pwsh%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*claude-clipboard-bridge*" -and $_.ProcessId -ne $PID }
foreach ($proc in $existingProcs) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($existingProcs) {
    Write-Host "  [OK] Stopped existing bridge process" -ForegroundColor Yellow
}

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "  [OK] Removed previous installation" -ForegroundColor Yellow
}

# Register scheduled task for auto-start
try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Silent" `
        -WorkingDirectory $scriptDir

    $trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description "Bridges clipboard images between Windows and Claude Code on WSL." |
        Out-Null

    Write-Host "  [OK] Auto-start registered (runs at login)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Could not register scheduled task." -ForegroundColor Red
    Write-Host "  Try running this installer as Administrator." -ForegroundColor Yellow
    Write-Host "  Error: $_" -ForegroundColor Gray
    Read-Host "Press Enter to exit"
    exit 1
}

# Create Start Menu shortcut
try {
    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $startMenuDir "Claude Clipboard Bridge.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Silent"
    $shortcut.WorkingDirectory = $scriptDir
    $shortcut.Description = "Claude Clipboard Bridge - Screenshot to WSL path"
    $shortcut.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    Write-Host "  [OK] Start Menu shortcut created" -ForegroundColor Green
} catch {
    Write-Host "  [--] Could not create Start Menu shortcut (non-critical)" -ForegroundColor Yellow
}

# Start it now
Start-ScheduledTask -TaskName $taskName
Write-Host "  [OK] Bridge started!" -ForegroundColor Green

Write-Host ""
Write-Host "  Installation complete!" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Look for the blue circle icon in your system tray." -ForegroundColor White
Write-Host ""
Write-Host "  How to use:" -ForegroundColor White
Write-Host "    1. Take a screenshot (Win+Shift+S)" -ForegroundColor Gray
Write-Host "    2. Switch to your terminal" -ForegroundColor Gray
Write-Host "    3. Ctrl+V" -ForegroundColor Gray
Write-Host ""
Write-Host "  Right-click the tray icon to pause, view logs," -ForegroundColor Gray
Write-Host "  open screenshots folder, or edit config." -ForegroundColor Gray
Write-Host ""

Read-Host "Press Enter to close"
