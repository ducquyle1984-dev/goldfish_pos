#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Goldfish POS cash drawer bridge startup task and files.
#>

$ErrorActionPreference = 'SilentlyContinue'

# Elevate to Administrator to remove the URL reservation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$TaskName = 'GoldfishPOS_CashDrawerBridge'
$AppDir   = "$env:APPDATA\GoldfishPOS"

Write-Host ''
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host '  Goldfish POS  —  Cash Drawer Bridge Uninstall  ' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host '  >> Stopping and removing startup task...' -ForegroundColor Cyan
Stop-ScheduledTask  -TaskName $TaskName
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host '  OK  Task removed.' -ForegroundColor Green

Write-Host '  >> Stopping bridge process...' -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host '  OK  Process stopped.' -ForegroundColor Green

Write-Host '  >> Removing HTTP namespace reservation...' -ForegroundColor Cyan
netsh http delete urlacl url='http://127.0.0.1:8765/' 2>&1 | Out-Null
Write-Host '  OK  URL reservation removed.' -ForegroundColor Green

Write-Host "  >> Removing files from $AppDir..." -ForegroundColor Cyan
Remove-Item $AppDir -Recurse -Force
Write-Host '  OK  Files removed.' -ForegroundColor Green

Write-Host ''
Write-Host '  Cash Drawer Bridge has been uninstalled.' -ForegroundColor Green
Write-Host ''
Read-Host 'Press Enter to close'
