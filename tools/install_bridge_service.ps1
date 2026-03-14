#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Goldfish POS Cash Drawer Bridge as a Windows startup task.
    No Python needed — uses built-in Windows PowerShell only.
    Safe to run multiple times; updates existing setup automatically.

.USAGE
    Double-click run_installer.bat
    (or right-click this file and choose "Run with PowerShell")
#>

$ErrorActionPreference = 'Stop'

# ── Self-elevate to Administrator ─────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$TaskName   = 'GoldfishPOS_CashDrawerBridge'
$AppDir     = "$env:APPDATA\GoldfishPOS"
$BridgeName = 'cash_drawer_bridge.ps1'
$BridgeSrc  = Join-Path $PSScriptRoot $BridgeName
$BridgeDest = Join-Path $AppDir $BridgeName
$LogDest    = Join-Path $AppDir 'bridge.log'

function Write-Step { param($m) Write-Host "  >> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  !!  $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "`n  ERROR: $m`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host '  Goldfish POS  —  Cash Drawer Bridge Installer  ' -ForegroundColor Cyan
Write-Host '  No Python needed  (PowerShell built-in only)   ' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Copy bridge script ─────────────────────────────────────────────────────
Write-Step "Installing bridge to: $AppDir"

if (-not (Test-Path $BridgeSrc)) {
    Write-Err "$BridgeName not found next to this installer.`nMake sure both files are in the same folder."
}

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $BridgeSrc $BridgeDest -Force
Write-Ok "Bridge script: $BridgeDest"

# ── 2. Reserve HTTP namespace so the bridge can run without admin rights ──────
Write-Step 'Reserving HTTP namespace for port 8765...'
$urlAcl = 'http://127.0.0.1:8765/'
netsh http delete urlacl url="$urlAcl" 2>&1 | Out-Null
$netshResult = netsh http add urlacl url="$urlAcl" user="$env:USERDOMAIN\$env:USERNAME" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "URL reservation skipped (non-critical): $netshResult"
} else {
    Write-Ok "HTTP namespace reserved for $env:USERNAME"
}

# ── 3. Register scheduled startup task ────────────────────────────────────────
Write-Step 'Registering Windows startup task...'

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$action    = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
             -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BridgeDest`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet `
             -ExecutionTimeLimit 0 `
             -RestartCount 10 `
             -RestartInterval (New-TimeSpan -Minutes 1) `
             -MultipleInstances IgnoreNew `
             -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Ok "Task '$TaskName' registered — starts automatically at every Windows logon."

# ── 4. Kill any old bridge instance + start fresh ─────────────────────────────
Write-Step 'Starting the bridge...'

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Milliseconds 500

if (Test-Path $LogDest) { Clear-Content $LogDest }
Start-Process -FilePath 'PowerShell.exe' `
    -ArgumentList "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BridgeDest`"" `
    -WindowStyle Hidden
Start-Sleep -Seconds 5

# ── 5. Verify bridge is responding ────────────────────────────────────────────
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
    Write-Host '=================================================' -ForegroundColor Green
    Write-Host '  SUCCESS!  Bridge is running.                   ' -ForegroundColor Green
    Write-Host '  Go back to the POS app and click Refresh (↻). ' -ForegroundColor Green
    Write-Host '=================================================' -ForegroundColor Green
} else {
    Write-Warn 'Bridge did not respond after 5 attempts. Log output:'
    Write-Host ''
    if (Test-Path $LogDest) {
        $lines = Get-Content $LogDest
        if ($lines) {
            $lines | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Host '    (log file is empty — the bridge may have crashed at startup)'
        }
    } else {
        Write-Host "    No log file found at: $LogDest"
    }
    Write-Host ''
    Write-Warn 'To see the error live: double-click run_bridge_debug.bat in the same folder.'
    Write-Warn 'Common fixes:'
    Write-Warn '  "Access is denied" → re-run this installer as Administrator'
    Write-Warn '  "No default printer" → set one in Windows Settings → Printers & scanners'
}

Write-Host ''
Write-Host '  To uninstall later, run: uninstall_bridge_service.ps1' -ForegroundColor Gray
Write-Host ''
Read-Host 'Press Enter to close'
