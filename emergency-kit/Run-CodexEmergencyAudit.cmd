@echo off
setlocal
title Codex Windows Emergency Audit

echo.
echo Codex Windows Emergency Read-Only Audit
echo ----------------------------------------
echo This tool works even when Codex Desktop and CLI cannot answer.
echo It also works offline and does not make network requests.
echo It will not delete files, stop processes, uninstall apps, or change system settings.
echo It creates only redacted diagnostic reports on the Windows Desktop.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-CodexEmergencyAudit.ps1"
set "audit_exit=%ERRORLEVEL%"

echo.
if not "%audit_exit%"=="0" (
  echo The audit did not finish. Keep a screenshot of the error above.
) else (
  echo Audit complete. Open the Codex-Emergency-Reports folder on your Desktop.
)
echo.
pause
exit /b %audit_exit%
