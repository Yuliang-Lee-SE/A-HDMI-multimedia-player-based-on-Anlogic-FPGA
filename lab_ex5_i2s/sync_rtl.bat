@echo off
rem One-way sync: TD project HDL sources -> lab_ex5_i2s\rtl (flat mirror for vendor testbenches).
rem Edit HDL under src\user_source\hdl_source, then run this script.
setlocal
set "BASE=%~dp0"
set "PRJ=%BASE%src\user_source\hdl_source"
set "DST=%BASE%rtl"
if not exist "%DST%" mkdir "%DST%"
call :copyone video_rgb_to_axis_640x480.v
call :copyone hdmi_audio_tone_i2s_64fs.v
call :copyone I2S_receiver.v
call :copyone audio_arc_calculate.v
call :copyone team\audio_rom_player.v
call :copyone SD\bmp_read.v
call :copyone SD\sd_card_top.v
call :copyone SD\sd_card_sec_read_write.v
call :copyone SD\sd_card_cmd.v
call :copyone SD\sd_card_bmp.v
call :copyone SD\spi_master.v
call :copyone SD\frame_fifo_write.v
call :copyone SD\frame_fifo_read.v
call :copyone SD\video_timing_data.v
call :copyone SD\color_bar.v
call :copyone SD\video_delay.v
call :copyone SD\video_define.v
call :copyone IP\afifo_16_32_256.v
call :copyone IP\afifo_32_16_256.v
echo [OK] lab_ex5_i2s\rtl refreshed from TD sources.
goto :eof
:copyone
copy /y "%PRJ%\%~1" "%DST%\" >nul
goto :eof
