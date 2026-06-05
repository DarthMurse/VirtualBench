@echo off
REM run_windows.bat — thin wrapper around run_windows.ps1 (the real logic lives there;
REM Job Objects and JSON handling need PowerShell). Forwards all arguments.
REM
REM Usage: scripts\run_windows.bat -Label host-baseline [-Reps 7] [-Config config.json]
setlocal
set "HERE=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%run_windows.ps1" %*
endlocal
