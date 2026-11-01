@echo off
rem One-way sync: TD project HDL sources -> lab_ex5_i2s\rtl (flat mirror for vendor testbenches).
rem Edit HDL under src\user_source\hdl_source, then run this script.
setlocal
set "BASE=%~dp0"
set "PRJ=%BASE%src\user_source\hdl_source"
set "DST=%BASE%rtl"
if not exist "%DST%" mkdir "%DST%"
call :copyone video_rgb_to_axis_640x480.v
call :copyone I2S_receiver.v
call :copyone audio_arc_calculate.v
call :copyone team\audio_pcm_player.v
call :copyone team\audio_spectrum_overlay.v
call :copyone team\board_key_debounce.v
call :copyone team\bmp_center_zoom_2x.v
call :copyone team\image_scaler_2x_pingpong.v
call :copyone team\osd_display_commit.v
call :copyone team\key_short_long.v
call :copyone team\picture_adjust_controller.v
call :copyone team\picture_adjust_pipeline.v
call :copyone team\picture_adjust_osd.v
call :copyone team\reset_startup_guard.v
call :copyone team\transition_frame_owner.v
call :copyone team\transition_mode_control.v
call :copyone team\waveform_overlay.v
call :copyone SD\spi_master.v
call :copyone SD\frame_fifo_write.v
call :copyone SD\frame_fifo_read.v
call :copyone SD\video_timing_data.v
call :copyone SD\video_delay.v
call :copyone IP\afifo_16_32_256.v
call :copyone IP\afifo_32_16_256.v
echo [OK] lab_ex5_i2s\rtl refreshed from TD sources.
goto :eof
:copyone
copy /y "%PRJ%\%~1" "%DST%\" >nul
goto :eof
