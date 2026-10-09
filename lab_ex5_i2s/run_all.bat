@echo off
rem ============================================================
rem  Pure-RTL subsystem simulation runner (ASCII only on purpose)
rem  Usage:  run_all.bat          -> run all 5 testbenches
rem          run_all.bat s1       -> run only S1 (s1..s5)
rem  Set MS to your ModelSim bin dir if vsim is not in PATH.
rem ============================================================
setlocal
set MS=D:\Modelsim\modelsim_ase\win32aloem
if not exist "%MS%\vsim.exe" set MS=

cd /d "%~dp0"

echo [1/2] compiling ...
"%MS%\vsim.exe" -c -l compile.log -do "do compile.do; quit -f"
if errorlevel 1 goto err

set ONLY=%1
if "%ONLY%"=="" set ONLY=all

if "%ONLY%"=="all" (
  call :run tb_bmp_read   "S1 bmp_read scan/parse"
  call :run tb_sd_card    "S2 SD card SPI stack"
  call :run tb_frame_fifo "S3 frame buffer read/write"
  call :run tb_audio_i2s  "S4 I2S audio chain"
  call :run tb_video_axis "S5 video timing + AXIS"
) else (
  if /i "%ONLY%"=="s1" call :run tb_bmp_read   "S1"
  if /i "%ONLY%"=="s2" call :run tb_sd_card    "S2"
  if /i "%ONLY%"=="s3" call :run tb_frame_fifo "S3"
  if /i "%ONLY%"=="s4" call :run tb_audio_i2s  "S4"
  if /i "%ONLY%"=="s5" call :run tb_video_axis "S5"
)
echo.
echo ==== done. logs are in this folder (tb_*.log) ====
goto :eof

:run
echo.
echo [2/2] running %~1  (%~2)
"%MS%\vsim.exe" -c -l %~1.log work.%~1 -do "run -all; quit -f"
findstr /C:"=== " %~1.log
goto :eof

:err
echo compile failed, see messages above
goto :eof
