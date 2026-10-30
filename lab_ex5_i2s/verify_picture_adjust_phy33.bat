@echo off
setlocal
set MS=D:\Modelsim\modelsim_ase\win32aloem
cd /d "%~dp0"

"%MS%\vlib.exe" picture_adjust_work
if errorlevel 1 goto err
"%MS%\vlog.exe" -work picture_adjust_work ^
    src/user_source/hdl_source/team/picture_adjust_controller.v ^
    src/user_source/hdl_source/team/picture_adjust_pipeline.v ^
    src/user_source/hdl_source/team/picture_adjust_osd.v ^
    tb_picture_adjust.v
if errorlevel 1 goto err
"%MS%\vlog.exe" -work picture_adjust_work ^
    src/user_source/hdl_source/top_tf_hdmi_audio.v
if errorlevel 1 goto err
"%MS%\vsim.exe" -c -l tb_picture_adjust.log ^
    picture_adjust_work.tb_picture_adjust -do "run -all; quit -f"
if errorlevel 1 goto err
findstr /C:"[FAIL]" /C:"[PASS]" /C:"=== PASS" /C:"=== FAIL" tb_picture_adjust.log
goto :eof

:err
echo picture adjustment verification failed
exit /b 1
