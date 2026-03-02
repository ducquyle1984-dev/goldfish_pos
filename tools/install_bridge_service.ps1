#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Goldfish POS cash drawer bridge as a Windows startup task.
    Run ONCE — the bridge then starts automatically every time Windows starts.

.DESCRIPTION
    This script will:
      1. Locate your Python installation (and install pywin32 if missing)
      2. Copy cash_drawer_bridge.py to a permanent location
      3. Register a Task Scheduler task that runs the bridge silently at logon
      4. Start the bridge immediately — no reboot needed

    Safe to run multiple times; updates the existing task if it already exists.
#>

$ErrorActionPreference = 'Stop'

$TaskName   = 'GoldfishPOS_CashDrawerBridge'
$AppDir     = "$env:APPDATA\GoldfishPOS"
$ScriptName = 'cash_drawer_bridge.py'
$ScriptSrc  = Join-Path $PSScriptRoot $ScriptName
$ScriptDest = Join-Path $AppDir $ScriptName

function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Err  { param($msg) Write-Host "`n  ERROR: $msg`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Goldfish POS  —  Cash Drawer Bridge Installer  ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Locate python.exe ──────────────────────────────────────────────────────
Write-Step 'Looking for Python 3...'

$pythonExe = $null
try { $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}

if (-not $pythonExe) {
    # Search common install paths
    $globs = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "C:\Python3*\python.exe",
        "C:\Program Files\Python3*\python.exe",
        "C:\Program Files (x86)\Python3*\python.exe"
    )
    foreach ($g in $globs) {
        $hit = Get-Item $g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { $pythonExe = $hit.FullName; break }
    }
}

if (-not $pythonExe) {
    Write-Err 'Python 3 not found. Install it from https://python.org — tick "Add Python to PATH" during setup, then re-run this script.'
}

Write-Ok "Found Python: $pythonExe"

# Use pythonw.exe (no console window) when available
$pythonwExe = Join-Path (Split-Path $pythonExe) 'pythonw.exe'
if (-not (Test-Path $pythonwExe)) {
    Write-Host '  (pythonw.exe not found — using python.exe; a small console may flash on startup)' -ForegroundColor Yellow
    $pythonwExe = $pythonExe
}

# ── 2. Ensure pywin32 is installed ────────────────────────────────────────────
Write-Step 'Checking for pywin32...'

$importTest = & $pythonExe -c "import win32print; print('ok')" 2>&1
if ("$importTest".Trim() -ne 'ok') {
    Write-Step 'pywin32 not found — installing now (may take a minute)...'

    $pipExe = Join-Path (Split-Path $pythonExe) 'Scripts\pip.exe'
    if (-not (Test-Path $pipExe)) { $pipExe = 'pip' }

    & $pipExe install pywin32 | Out-Host

    $importTest = & $pythonExe -c "import win32print; print('ok')" 2>&1
    if ("$importTest".Trim() -ne 'ok') {
        Write-Err "pywin32 installation failed: $importTest"
    }
}

Write-Ok 'pywin32 is ready.'

# ── 2b. Run pywin32 post-install (registers DLLs — required on some systems) ──
Write-Step 'Running pywin32 post-install step...'
$postInstall = Join-Path (Split-Path $pythonExe) 'Scripts\pywin32_postinstall.py'
if (Test-Path $postInstall) {
    & $pythonExe $postInstall -install 2>&1 | Out-Null
    Write-Ok 'pywin32 post-install complete.'
} else {
    Write-Host '  (pywin32_postinstall.py not found — skipping, likely not needed)' -ForegroundColor Yellow
}

# Verify import actually works after post-install
$importTest2 = & $pythonExe -c "import win32print; print('ok')" 2>&1
if ("$importTest2".Trim() -ne 'ok') {
    Write-Err "win32print still cannot be imported after post-install: $importTest2"
}
Write-Ok 'win32print import verified.'

# ── 3. Copy bridge script to permanent location ───────────────────────────────
Write-Step "Installing bridge script to: $AppDir"

if (-not (Test-Path $ScriptSrc)) {
    Write-Err "Cannot find $ScriptSrc.`nMake sure you are running this installer from the project's tools\ folder."
}

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $ScriptSrc $ScriptDest -Force

Write-Ok "Script copied to: $ScriptDest"

# ── 4. Register scheduled task ────────────────────────────────────────────────
Write-Step 'Registering Windows startup task...'

# Remove any old version first
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$action = New-ScheduledTaskAction `
    -Execute  $pythonwExe `
    -Argument "`"$ScriptDest`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit  0 `
    -RestartCount        5 `
    -RestartInterval     (New-TimeSpan -Minutes 1) `
    -MultipleInstances   IgnoreNew `
    -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId   "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Ok "Task '$TaskName' registered (runs at every Windows logon)."

# ── 5. Start the bridge right now ─────────────────────────────────────────────
Write-Step 'Starting the bridge...'

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

$taskState = (Get-ScheduledTask -TaskName $TaskName).State
if ($taskState -eq 'Running') {
    Write-Ok 'Bridge is running now!'
} else {
    Write-Host "  Note: bridge state is '$taskState'. It will start automatically on your next logon." -ForegroundColor Yellow
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '==================================================' -ForegroundColor Green
Write-Host '  Setup complete!                                  ' -ForegroundColor Green
Write-Host '  The cash drawer bridge will now start           ' -ForegroundColor Green
Write-Host '  automatically every time Windows starts.        ' -ForegroundColor Green
Write-Host '  No further action needed.                       ' -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  To uninstall later, run: uninstall_bridge_service.ps1" -ForegroundColor Gray
Write-Host ''
Read-Host 'Press Enter to close'
