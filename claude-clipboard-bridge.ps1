# ============================================================
# Claude Clipboard Bridge
# ============================================================
# A system tray app that bridges clipboard images between
# Windows and Claude Code running in WSL.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File claude-clipboard-bridge.ps1
#
# How it works:
#   - Runs as a system tray icon
#   - Detects new clipboard images and saves them to disk
#   - Context-aware: swaps clipboard based on focused window
#     - Terminal focused: clipboard = WSL file path
#     - Other app focused: clipboard = original image
#   - Just screenshot, switch to terminal, Ctrl+V
# ============================================================

param(
    [string]$SaveDir = "C:\tmp\claude-clipboard",
    [string]$WslMountPrefix = "/mnt",
    [int]$PollIntervalMs = 500,
    [int]$MaxHistory = 10,
    [switch]$Silent,
    [switch]$Version
)

# --- Version ---
$AppVersion = "1.0.0"

if ($Version) {
    Write-Host "Claude Clipboard Bridge v$AppVersion"
    exit 0
}

# --- PowerShell version guard ---
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host "Claude Clipboard Bridge requires Windows PowerShell (powershell.exe), not PowerShell Core (pwsh.exe)." -ForegroundColor Red
    Write-Host "Run with: powershell.exe -ExecutionPolicy Bypass -File claude-clipboard-bridge.ps1" -ForegroundColor Yellow
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$csharpCode = @'
using System;
using System.Runtime.InteropServices;

public class ClipboardNative {
    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();
}

public class ForegroundWindow {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public static string GetForegroundProcessName() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return "";
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        try {
            var proc = System.Diagnostics.Process.GetProcessById((int)pid);
            return proc.ProcessName.ToLower();
        } catch {
            return "";
        }
    }
}

public class IconHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies System.Drawing

# --- Load config ---
$configPath = Join-Path $PSScriptRoot "config.json"
$defaultConfig = @{
    SaveDir = $SaveDir
    WslMountPrefix = $WslMountPrefix
    PollIntervalMs = $PollIntervalMs
    MaxHistory = $MaxHistory
    TerminalProcesses = @(
        "windowsterminal",
        "cmd",
        "powershell",
        "pwsh",
        "mintty",
        "conhost",
        "alacritty",
        "wezterm-gui",
        "hyper",
        "code",
        "cursor",
        "kitty",
        "tabby",
        "rio",
        "ghostty"
    )
    ShowNotifications = $true
}

if (Test-Path $configPath) {
    try {
        $fileConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $fileConfig.PSObject.Properties) {
            $defaultConfig[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Warning "Could not read config.json, using defaults."
    }
}

$config = $defaultConfig
$SaveDir = $config.SaveDir
$WslMountPrefix = $config.WslMountPrefix
$PollIntervalMs = $config.PollIntervalMs
$MaxHistory = $config.MaxHistory
# Lowercase all terminal process names for case-insensitive matching
$terminalProcesses = @($config.TerminalProcesses | ForEach-Object { $_.ToLower() })

# --- Helpers ---
function Convert-ToWslPath {
    param([string]$WinPath)
    $driveLetter = $WinPath.Substring(0, 1).ToLower()
    $rest = $WinPath.Substring(3) -replace '\\', '/'
    return "$WslMountPrefix/$driveLetter/$rest"
}

function Test-IsTerminalFocused {
    $procName = [ForegroundWindow]::GetForegroundProcessName()
    return $terminalProcesses -contains $procName
}

function Cleanup-OldImages {
    $images = Get-ChildItem -Path $SaveDir -Filter "clip_*.png" -File |
              Sort-Object CreationTime -Descending |
              Select-Object -Skip $MaxHistory
    foreach ($old in $images) {
        Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
    }
}

# --- Setup ---
if (-not (Test-Path $SaveDir)) {
    try {
        New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null
    } catch {
        Write-Host "Cannot create $SaveDir - check permissions." -ForegroundColor Red
        exit 1
    }
}

$logFile = Join-Path $SaveDir "bridge.log"

$latestPath = Join-Path $SaveDir "latest.png"
$latestWslPath = Convert-ToWslPath $latestPath

# --- Create and cache tray icons (avoids GDI handle leak) ---
function New-CachedIcon {
    param([System.Drawing.Color]$FillColor, [System.Drawing.Color]$BorderColor)
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $fillBrush = New-Object System.Drawing.SolidBrush($FillColor)
    $borderPen = New-Object System.Drawing.Pen($BorderColor)
    $g.FillEllipse($fillBrush, 2, 2, 12, 12)
    $g.DrawEllipse($borderPen, 2, 2, 12, 12)
    $fillBrush.Dispose()
    $borderPen.Dispose()
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
    [IconHelper]::DestroyIcon($hIcon)
    $bmp.Dispose()
    return $icon
}

$iconReady = New-CachedIcon ([System.Drawing.Color]::DodgerBlue) ([System.Drawing.Color]::DarkBlue)
$iconActive = New-CachedIcon ([System.Drawing.Color]::LimeGreen) ([System.Drawing.Color]::DarkGreen)
$iconPaused = New-CachedIcon ([System.Drawing.Color]::Gray) ([System.Drawing.Color]::DarkGray)

# --- System Tray ---
$script:running = $true
$script:paused = $false
$script:imageCount = 0

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = $iconReady
$notifyIcon.Text = "Claude Clipboard Bridge - Ready"
$notifyIcon.Visible = $true

# Context menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = "Status: Ready"
$statusItem.Enabled = $false
$contextMenu.Items.Add($statusItem) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$pauseItem = New-Object System.Windows.Forms.ToolStripMenuItem
$pauseItem.Text = "Pause"
$pauseItem.Add_Click({
    if ($script:paused) {
        $script:paused = $false
        $pauseItem.Text = "Pause"
        $notifyIcon.Icon = $iconReady
        $notifyIcon.Text = "Claude Clipboard Bridge - Ready"
        $statusItem.Text = "Status: Ready"
    } else {
        $script:paused = $true
        $pauseItem.Text = "Resume"
        $notifyIcon.Icon = $iconPaused
        $notifyIcon.Text = "Claude Clipboard Bridge - Paused"
        $statusItem.Text = "Status: Paused"
    }
})
$contextMenu.Items.Add($pauseItem) | Out-Null

$folderItem = New-Object System.Windows.Forms.ToolStripMenuItem
$folderItem.Text = "Open Screenshots Folder"
$folderItem.Add_Click({ Start-Process explorer.exe -ArgumentList $SaveDir })
$contextMenu.Items.Add($folderItem) | Out-Null

$configItem = New-Object System.Windows.Forms.ToolStripMenuItem
$configItem.Text = "Edit Config"
$configItem.Add_Click({
    if (-not (Test-Path $configPath)) {
        $config | ConvertTo-Json -Depth 3 | Set-Content $configPath -Encoding UTF8
    }
    Start-Process notepad.exe -ArgumentList $configPath
})
$contextMenu.Items.Add($configItem) | Out-Null

$logItem = New-Object System.Windows.Forms.ToolStripMenuItem
$logItem.Text = "View Log"
$logItem.Add_Click({
    if (Test-Path $logFile) { Start-Process notepad.exe -ArgumentList $logFile }
})
$contextMenu.Items.Add($logItem) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem
$aboutItem.Text = "About"
$aboutItem.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "Claude Clipboard Bridge v$AppVersion`n`nBridges clipboard images between Windows and Claude Code on WSL.`n`nScreenshot anywhere, switch to terminal, Ctrl+V.`nSwitch back - clipboard is the image again.`n`ngithub.com/aboudzein/claude-clipboard-bridge",
        "About Claude Clipboard Bridge",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
})
$contextMenu.Items.Add($aboutItem) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "Exit"
$exitItem.Add_Click({
    $script:running = $false
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.Items.Add($exitItem) | Out-Null

$notifyIcon.ContextMenuStrip = $contextMenu
$notifyIcon.Add_DoubleClick({ $pauseItem.PerformClick() })

# Show startup notification
if (-not $Silent -and $config.ShowNotifications) {
    $notifyIcon.BalloonTipTitle = "Claude Clipboard Bridge"
    $notifyIcon.BalloonTipText = "Running! Screenshot anywhere, switch to terminal, Ctrl+V."
    $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $notifyIcon.ShowBalloonTip(3000)
}

# --- State ---
$script:lastSeqNum = [ClipboardNative]::GetClipboardSequenceNumber()
$script:lastImageHash = ""
$script:clipState = "none"
$script:wasInTerminal = $false
$script:skipNextSeqChange = $false
$script:cycleCount = 0

# --- Timer-based main loop ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollIntervalMs
$timer.Add_Tick({
    if ($script:paused) { return }

    try {
        # --- Detect new clipboard images ---
        $currentSeqNum = [ClipboardNative]::GetClipboardSequenceNumber()
        if ($currentSeqNum -ne $script:lastSeqNum) {
            $script:lastSeqNum = $currentSeqNum

            if ($script:skipNextSeqChange) {
                $script:skipNextSeqChange = $false
            } else {
                $img = $null
                try { $img = [System.Windows.Forms.Clipboard]::GetImage() } catch {}

                if ($img) {
                    $ms = $null
                    $sha = $null
                    try {
                        $ms = New-Object System.IO.MemoryStream
                        $img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                        $bytes = $ms.ToArray()
                        $sha = [System.Security.Cryptography.SHA256]::Create()
                        $hash = [BitConverter]::ToString($sha.ComputeHash($bytes))

                        if ($hash -ne $script:lastImageHash) {
                            $script:lastImageHash = $hash

                            $tempPath = "$latestPath.tmp"
                            $img.Save($tempPath)
                            Move-Item -Path $tempPath -Destination $latestPath -Force

                            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                            $historyPath = Join-Path $SaveDir "clip_$timestamp.png"
                            Copy-Item -Path $latestPath -Destination $historyPath -Force
                            Cleanup-OldImages

                            $script:clipState = "image"
                            $script:wasInTerminal = $false
                            $script:imageCount++

                            $notifyIcon.Icon = $iconActive
                            $notifyIcon.Text = "Claude Clipboard Bridge - Screenshot ready!"
                            $statusItem.Text = "Status: Screenshot ready ($($script:imageCount) total)"

                            if ($config.ShowNotifications) {
                                $notifyIcon.BalloonTipTitle = "Screenshot Saved"
                                $notifyIcon.BalloonTipText = "Switch to terminal and Ctrl+V to paste."
                                $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
                                $notifyIcon.ShowBalloonTip(2000)
                            }
                        }
                    } finally {
                        if ($sha) { $sha.Dispose() }
                        if ($ms) { $ms.Dispose() }
                        $img.Dispose()
                    }
                } else {
                    # Clipboard changed to non-image by user
                    $script:clipState = "none"
                    $notifyIcon.Icon = $iconReady
                    $notifyIcon.Text = "Claude Clipboard Bridge - Ready"
                    $statusItem.Text = "Status: Ready ($($script:imageCount) screenshots)"
                }
            }
        }

        # --- Context-aware clipboard swap ---
        if ($script:clipState -ne "none") {
            $inTerminal = Test-IsTerminalFocused

            if ($inTerminal -and -not $script:wasInTerminal) {
                # Switched TO terminal - set clipboard to path
                try {
                    [System.Windows.Forms.Clipboard]::SetText($latestWslPath)
                    $script:skipNextSeqChange = $true
                    $script:clipState = "path"
                } catch {}
                $script:wasInTerminal = $true
                $notifyIcon.Text = "Claude Clipboard Bridge - Path ready, Ctrl+V!"
                $statusItem.Text = "Status: Path in clipboard - Ctrl+V!"
            }
            elseif (-not $inTerminal -and $script:wasInTerminal) {
                # Switched AWAY from terminal - restore image
                if (Test-Path $latestPath) {
                    $restoreImg = $null
                    try {
                        $restoreImg = [System.Drawing.Image]::FromFile($latestPath)
                        [System.Windows.Forms.Clipboard]::SetImage($restoreImg)
                        $script:skipNextSeqChange = $true
                        $script:clipState = "image"
                        $notifyIcon.Text = "Claude Clipboard Bridge - Image restored"
                        $statusItem.Text = "Status: Image in clipboard"
                    } catch {} finally {
                        if ($restoreImg) { $restoreImg.Dispose() }
                    }
                }
                $script:wasInTerminal = $false
            }
        }

        # Periodic GC
        $script:cycleCount++
        if ($script:cycleCount -ge 200) {
            [System.GC]::Collect()
            $script:cycleCount = 0
        }

    } catch [System.Runtime.InteropServices.ExternalException] {
        # Clipboard busy
    } catch {
        try {
            $errMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Error: $_"
            Add-Content -Path $logFile -Value $errMsg -ErrorAction SilentlyContinue
        } catch {}
    }
})

$timer.Start()
[System.Windows.Forms.Application]::Run()
