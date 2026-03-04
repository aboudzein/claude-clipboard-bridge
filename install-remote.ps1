# ============================================================
# Claude Clipboard Bridge - Remote Installer
# ============================================================
# Run this one-liner in PowerShell to install:
#   irm https://raw.githubusercontent.com/aboudzein/claude-clipboard-bridge/main/install-remote.ps1 | iex
# ============================================================

trap {
    Write-Host "  [ERROR] Installation failed: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    break
}

$ErrorActionPreference = "Stop"
$repo = "aboudzein/claude-clipboard-bridge"
$branch = "main"
$installDir = Join-Path $env:LOCALAPPDATA "claude-clipboard-bridge"
$baseUrl = "https://raw.githubusercontent.com/$repo/$branch"

Write-Host ""
Write-Host "  Claude Clipboard Bridge - Installer" -ForegroundColor Cyan
Write-Host "  ====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Downloading from github.com/$repo ..." -ForegroundColor Gray

# Create install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Files to download
$files = @(
    "claude-clipboard-bridge.ps1",
    "install.ps1",
    "uninstall.ps1"
)

foreach ($file in $files) {
    $url = "$baseUrl/$file"
    $dest = Join-Path $installDir $file
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Write-Host "  [OK] $file" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Could not download $file" -ForegroundColor Red
        Write-Host "  URL: $url" -ForegroundColor Gray
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Only download config if it doesn't exist (preserve user customizations)
$configDest = Join-Path $installDir "config.json"
if (-not (Test-Path $configDest)) {
    try {
        Invoke-WebRequest -Uri "$baseUrl/config.json" -OutFile $configDest -UseBasicParsing
        Write-Host "  [OK] config.json" -ForegroundColor Green
    } catch {
        Write-Host "  [--] config.json download skipped (will use defaults)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [--] config.json exists, keeping your settings" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Downloaded to: $installDir" -ForegroundColor Gray
Write-Host ""

# Run the local installer (bypass execution policy for the downloaded file)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir "install.ps1")
