@echo off
echo.
echo  Goldfish POS -- Cash Drawer Bridge Installer
echo  ============================================
echo  Starting installer with administrator rights...
echo.
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_bridge_service.ps1"
