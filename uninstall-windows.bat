@echo off
rem ExternalSoundboard uninstaller: double-click to run. Downloads and runs uninstall.ps1 (or the one next to this file).
if exist "%~dp0uninstall.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/uninstall.ps1 | iex"
)
echo.
pause
