#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Goldfish POS cash drawer bridge as a Windows startup task.
    No pip install or pywin32 needed — uses only Python standard library (ctypes).
    Safe to run multiple times; updates the existing task if it already exists.

.USAGE
    Right-click install_bridge_service.ps1 → Run with PowerShell
    (or run run_installer.bat which handles the ExecutionPolicy for you)
#>

$ErrorActionPreference = 'Stop'

# ── Self-elevate to Administrator ─────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '  Requesting administrator rights...' -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$TaskName     = 'GoldfishPOS_CashDrawerBridge'
$AppDir       = "$env:APPDATA\GoldfishPOS"
$ScriptName   = 'cash_drawer_bridge.py'
$ScriptSrc    = Join-Path $PSScriptRoot $ScriptName
$ScriptDest   = Join-Path $AppDir $ScriptName
$LauncherDest = Join-Path $AppDir 'run_bridge.bat'
$LogDest      = Join-Path $AppDir 'bridge.log'

function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  !!  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "`n  ERROR: $msg`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Goldfish POS  —  Cash Drawer Bridge Installer  ' -ForegroundColor Cyan
Write-Host '   No pip install needed (standard library only)  ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Locate Python ──────────────────────────────────────────────────────────
Write-Step 'Looking for Python 3...'

$pythonExe = $null
try { $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}

if (-not $pythonExe) {
    $globs = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        'C:\Python3*\python.exe',
        'C:\Program Files\Python3*\python.exe',
        'C:\Program Files (x86)\Python3*\python.exe'
    )
    foreach ($g in $globs) {
        $hit = Get-Item $g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { $pythonExe = $hit.FullName; break }
    }
}

if (-not $pythonExe) {
    Write-Err 'Python 3 not found.
Install it from https://python.org — tick "Add Python to PATH" during setup — then re-run this script.'
}

# Reject Microsoft Store Python — it is a stub that cannot run scripts reliably
if ($pythonExe -like '*WindowsApps*') {
    Write-Err "Found Microsoft Store Python at:
  $pythonExe

This version is NOT compatible. Please:
  1. Go to https://python.org and download the real installer.
  2. During install, check 'Add Python to PATH'.
  3. Re-run this script."
}

$pyVer = & $pythonExe --version 2>&1
Write-Ok "Python: $pythonExe  ($pyVer)"

# ── 2. Verify standard library modules (no pip needed) ───────────────────────
Write-Step 'Verifying required modules (standard library only — no pip needed)...'

$check = & $pythonExe -c "import ctypes, ctypes.wintypes, subprocess, socket, json, logging; print('ok')" 2>&1
if ("$check".Trim() -ne 'ok') {
    Write-Err "Standard library check failed:
$check

This is unexpected. Try a fresh Python install from https://python.org"
}
Write-Ok 'All required modules present.'

# ── 3. Copy bridge script ─────────────────────────────────────────────────────
Write-Step "Installing bridge to: $AppDir"

if (-not (Test-Path $ScriptSrc)) {
    Write-Err "Cannot find $ScriptSrc.
Make sure you are running this installer from the project tools\ folder."
}

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $ScriptSrc $ScriptDest -Force
Write-Ok "Script copied to: $ScriptDest"

# Write .bat launcher — redirects stdout+stderr to bridge.log
$bat = "@echo off`r`n`"$pythonExe`" `"$ScriptDest`" >> `"$LogDest`" 2>&1`r`n"
[System.IO.File]::WriteAllText($LauncherDest, $bat, [System.Text.Encoding]::ASCII)
Write-Ok "Launcher: $LauncherDest"

# ── 4. Register scheduled startup task ────────────────────────────────────────
Write-Step 'Registering Windows startup task...'

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$LauncherDest`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit  0 `
    -RestartCount        10 `
    -RestartInterval     (New-TimeSpan -Minutes 1) `
    -MultipleInstances   IgnoreNew `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Ok "Task '$TaskName' registered — runs automatically at every Windows logon."

# ── 5. Kill any old instance + start fresh ────────────────────────────────────
Write-Step 'Starting the bridge...'

Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

if (Test-Path $LogDest) { Clear-Content $LogDest }
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$LauncherDest`"" -WindowStyle Hidden
Start-Sleep -Seconds 4

# ── 6. Verify bridge is responding ────────────────────────────────────────────
Write-Step 'Verifying bridge at http://127.0.0.1:8765/status ...'

$ok = $false
for ($i = 0; $i -lt 5; $i++) {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8765/status' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch {}
    Write-Host "    attempt $($i+1)/5 — waiting..."
    Start-Sleep -Seconds 2
}

Write-Host ''
if ($ok) {
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host '  SUCCESS! Bridge is running.                     ' -ForegroundColor Green
    Write-Host '  Go back to the POS app and click Refresh (↻).  ' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Warn 'Bridge did not respond after 5 attempts. Log output:'
    Write-Host ''
    if (Test-Path $LogDest) {
        $lines = Get-Content $LogDest
        if ($lines) {
            $lines | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Host '    (log file is empty — Python may have crashed before writing anything)'
        }
    } else {
        Write-Host '    No log file found.'
        Write-Host "    Python:   $pythonExe"
        Write-Host "    Launcher: $LauncherDest"
    }
    Write-Host ''
    Write-Warn 'To diagnose: double-click run_bridge_debug.bat in the same folder.'
    Write-Warn 'Common fixes:'
    Write-Warn '  "No default printer" → set one in Windows Settings → Printers & scanners'
    Write-Warn '  Any import error → try a fresh Python install from https://python.org'
}

Write-Host ''
Write-Host "  To uninstall later, run: uninstall_bridge_service.ps1" -ForegroundColor Gray
Write-Host ''
Read-Host 'Press Enter to close'
