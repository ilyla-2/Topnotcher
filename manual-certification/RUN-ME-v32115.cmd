@echo off
setlocal
cd /d "%~dp0"
echo.
echo CELE Topnotcher OS - v3.21.15 Manual Desktop UI Certification
echo =============================================================
echo.
echo This will verify and use the exact frozen unsigned RC2 installer.
echo It will NOT approve a public release automatically.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-v32115-desktop-ui-cert.ps1" -InstallerPath "%~dp0CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe" -OutputDirectory "%~dp0CELE-v3.21.15-manual-desktop-ui-evidence"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Certification script ended with exit code %EXITCODE%.
) else (
  echo Certification script completed.
)
echo.
pause
exit /b %EXITCODE%
