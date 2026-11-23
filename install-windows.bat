@echo off
rem Double-click installer for Windows. Works from a full download, or on its own (it then fetches install.ps1).
if exist "%~dp0install.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/install.ps1 | iex"
)
pause
