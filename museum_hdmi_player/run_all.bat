@echo off
rem Compatibility entry point. Use the single maintained regression runner.
if "%~1"=="" (
  powershell -ExecutionPolicy Bypass -File "%~dp0..\scripts\run_regression.ps1"
) else (
  powershell -ExecutionPolicy Bypass -File "%~dp0..\scripts\run_regression.ps1" -Only "%~1"
)
exit /b %errorlevel%
