@echo off
setlocal
where pwsh >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Install it and add pwsh to PATH.
  pause
  exit /b 1
)
pwsh -NoLogo -NoProfile -File "%~dp0console-demo.ps1" -InboxRoot "%~dp0sample"
endlocal
