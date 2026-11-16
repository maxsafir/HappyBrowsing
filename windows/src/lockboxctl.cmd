@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lockboxctl.ps1" %*
