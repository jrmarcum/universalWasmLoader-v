@echo off
rem Use `zig cc` as V's C compiler (no Git Bash needed; dispatches to PowerShell).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0zigcc.ps1" %*
