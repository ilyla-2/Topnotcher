@echo off
setlocal
cd /d "%~dp0"
echo.
echo CELE Topnotcher OS - RC5 Real Preboard Regression Retest
echo =======================================================
echo.
echo This installs the exact v3.21.20 RC5 and retests the SAME
echo preboard PDF that made RC4 become Not Responding.
echo.
echo The monitor records whether the Windows app process stays responsive.
echo It does NOT approve DPI, signing, redistribution, or public release.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-v32121-rc5-preboard-retest.ps1" -InstallerPath "%~dp0CELE-Topnotcher-OS-v3.21.20-RC5-unsigned-setup.exe" -OutputDirectory "%~dp0CELE-v3.21.21-RC5-preboard-retest-evidence"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo Retest script ended with exit code %EXITCODE%.
) else (
  echo Retest script completed.
)
echo.
pause
exit /b %EXITCODE%
