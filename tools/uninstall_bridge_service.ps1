#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the Goldfish POS cash drawer bridge startup task.
#>

$ErrorActionPreference = 'SilentlyContinue'

$TaskName = 'GoldfishPOS_CashDrawerBridge'
$AppDir   = "$env:APPDATA\GoldfishPOS"

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '  Goldfish POS  —  Cash Drawer Bridge Uninstaller ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host '  >> Stopping bridge task...' -ForegroundColor Cyan
Stop-ScheduledTask  -TaskName $TaskName
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host '  OK  Task removed.' -ForegroundColor Green

Write-Host "  >> Removing files from $AppDir..." -ForegroundColor Cyan
Remove-Item $AppDir -Recurse -Force
Write-Host '  OK  Files removed.' -ForegroundColor Green

Write-Host ''
Write-Host '  Cash Drawer Bridge has been uninstalled.' -ForegroundColor Green
Write-Host ''
Read-Host 'Press Enter to close'
