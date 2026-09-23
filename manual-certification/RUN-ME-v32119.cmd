@echo off
setlocal
cd /d "%~dp0"
echo.
echo CELE Topnotcher OS - v3.21.19 RC4 Manual Desktop UI Certification
echo ================================================================
echo.
echo This verifies and installs the corrected unsigned RC4 build.
echo It replaces any earlier 0.3.6 RC2 candidate before testing.
echo It will NOT approve a public release automatically.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-v32119-desktop-ui-cert.ps1" -InstallerPath "%~dp0CELE-Topnotcher-OS-v3.21.18-RC4-unsigned-setup.exe" -OutputDirectory "%~dp0CELE-v3.21.19-manual-desktop-ui-evidence"
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
