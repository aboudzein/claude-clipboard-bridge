# Claude Clipboard Bridge

![Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

> Paste screenshots into Claude Code on WSL -- just like on Mac.

## Why?

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) is Anthropic's CLI for AI-assisted development. On Mac, you can paste screenshots directly into Claude Code. On WSL, you can't -- the terminal doesn't support clipboard image data.

This bridge fills that gap with zero friction.

## How it works

```
Screenshot (Win+Shift+S)  -->  Switch to terminal  -->  Ctrl+V  -->  Done
```

The bridge is a lightweight system tray app that watches your clipboard and which window is focused:

| Focused window | Clipboard contains |
|---|---|
| Terminal (Windows Terminal, VS Code, etc.) | WSL file path to the image |
| Any other app (browser, Figma, etc.) | Original image |

It swaps automatically as you alt-tab. Your clipboard always has the right thing for the right context.

<!-- Add a demo GIF here: ![Demo](docs/demo.gif) -->

## Install

### Option 1: One-liner (recommended)

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/aboudzein/claude-clipboard-bridge/main/install-remote.ps1 | iex
```

> **What does this run?** You can [read the installer source](install-remote.ps1) before running.
> It downloads files to `%LOCALAPPDATA%\claude-clipboard-bridge` and creates a scheduled task.
> No admin privileges required. No data leaves your machine.

### Option 2: Download

1. [Download the latest release](https://github.com/aboudzein/claude-clipboard-bridge/releases) or clone the repo
2. Double-click `install.bat`

That's it. A blue circle appears in your system tray.

### What the installer does

- Downloads files to `%LOCALAPPDATA%\claude-clipboard-bridge`
- Creates a scheduled task to auto-start at login
- Adds a Start Menu shortcut (searchable from Windows search)
- Starts the bridge immediately

## Uninstall

### Option 1: One-liner

```powershell
& "$env:LOCALAPPDATA\claude-clipboard-bridge\uninstall.ps1"
```

### Option 2: Manual

Double-click `uninstall.bat`

## System Tray

The tray icon shows the current status:

- **Blue** -- Ready, waiting for screenshots
- **Green** -- Screenshot saved, ready to paste
- **Gray** -- Paused

Right-click the tray icon for:
- **Pause / Resume** -- temporarily disable the bridge
- **Open Screenshots Folder** -- view saved images
- **Edit Config** -- customize settings
- **View Log** -- check for errors
- **Exit** -- stop the bridge

Double-click the icon to toggle pause.

## Configuration

Edit `config.json` (or right-click tray icon -> Edit Config):

```json
{
  "SaveDir": "C:\\tmp\\claude-clipboard",
  "WslMountPrefix": "/mnt",
  "PollIntervalMs": 500,
  "MaxHistory": 10,
  "ShowNotifications": true,
  "TerminalProcesses": ["windowsterminal", "cmd", "code", "cursor", ...]
}
```

| Setting | Description |
|---|---|
| `SaveDir` | Where screenshots are saved on Windows |
| `WslMountPrefix` | WSL mount prefix (usually `/mnt`) |
| `PollIntervalMs` | How often to check clipboard (ms) |
| `MaxHistory` | Number of screenshots to keep |
| `ShowNotifications` | Show balloon notifications |
| `TerminalProcesses` | Process names recognized as terminals |

### Finding your terminal's process name

If your terminal isn't detected, find its process name:

1. Focus your terminal window
2. Open another PowerShell and run: `(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object ProcessName)`
3. Add the process name (lowercase) to `TerminalProcesses` in `config.json`

## How it works (technical)

1. **Efficient polling** -- Uses Win32 `GetClipboardSequenceNumber()` to detect changes with near-zero CPU cost. Only processes the clipboard when it actually changes.

2. **Image detection** -- When the clipboard contains a new image, saves it to disk with SHA-256 dedup and atomic writes (temp file + rename).

3. **Context switching** -- Uses `GetForegroundWindow()` + `GetWindowThreadProcessId()` to detect which app is focused. When you switch to a terminal, replaces the clipboard image with the WSL file path. When you switch away, restores the original image.

4. **Resource management** -- Cached GDI+ icons (no handle leak), proper `try/finally` disposal, periodic garbage collection, and image history cleanup.

## Troubleshooting

**The tray icon doesn't appear**
- Check if it's hidden in the system tray overflow (click the `^` arrow in the taskbar)
- Try restarting: search "Claude Clipboard Bridge" in the Start Menu

**Screenshot not detected**
- Make sure the bridge is running (look for the blue/green tray icon)
- The bridge only detects image data on the clipboard, not file copies

**Wrong terminal detected / not detected**
- Right-click tray icon -> Edit Config
- Add your terminal's process name to `TerminalProcesses` (see [Finding your terminal's process name](#finding-your-terminals-process-name))

**Path doesn't work in Claude Code**
- Make sure WSL can access the path: `ls /mnt/c/tmp/claude-clipboard/latest.png`
- If your WSL mount point isn't `/mnt`, update `WslMountPrefix` in config

**Works with WSL 1?**
- Yes, both WSL 1 and WSL 2 mount Windows drives at `/mnt/c` by default

**Does this send my screenshots anywhere?**
- No. Everything is 100% local. Screenshots are saved to your disk and never uploaded.

## Requirements

- Windows 10/11 with WSL
- Windows PowerShell 5.1+ (included with Windows, NOT PowerShell Core/pwsh)
- A terminal (Windows Terminal recommended)

## Contributing

Issues and PRs welcome! This is a single-file PowerShell script -- easy to hack on.

## License

MIT
