param(
 [string]$Vsim='D:/j1573/modelsim/modelsim_ase/win32aloem/vsim.exe',
 [string]$Python='python',
 [switch]$SkipLongSdram,
 [string]$ValidateLogOnly
)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 if($ValidateLogOnly){$log=$ValidateLogOnly} else {
 & $Python tools/test_osd_resources.py
 if($LASTEXITCODE -ne 0){throw 'Resource checks failed'}
 & $Python tools/prepare_osd_validation.py
 if($LASTEXITCODE -ne 0){throw 'Golden preparation failed'}
 $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
 $commands='do run_osd_validation.do; do run_osd_video_commit.do; do run_board_zoom_tests.do; do run_board_zoom_control_tests.do; set display_commit 1; do run_board_zoom_control_tests.do; do run_board_zoom_fifo_tests.do; '
 if(!$SkipLongSdram){$commands+='set diag_height 480; do run_zoom_real_sdram.do; set diag_height 48; set forced_refresh 1; do run_zoom_real_sdram.do; '}
 $commands+='quit -f'
 $log="osd_validation_$stamp.log"
 & $Vsim -c -do $commands -l $log
 if($LASTEXITCODE -ne 0){throw "Simulation failed: $log"}
 }
 $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $log))
 $markers=@('OSD PIXELS COMPLETE checked=2150400 errors=0','OSD ROM COMPLETE errors=0','OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0','REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0','[TEST PASS] BMP center zoom and 1x/2x/1x frame switching are correct.','[TEST PASS] Board zoom controller integration is correct.','[TEST PASS] Center zoom to original FIFO/address scheduler is correct.')
 if($text -match '\[FAIL\]|\[TEST FAIL\]|\*\* Error:'){throw "Failed simulation: $log"}
 foreach($marker in $markers){if(!$text.Contains($marker)){throw "Missing pass marker: $marker ($log)"}}
 if(([regex]::Matches($text,[regex]::Escape('[TEST PASS] Board zoom controller integration is correct.'))).Count -ne 2){throw 'Both controller configurations must pass'}
 if(!$SkipLongSdram -and ([regex]::Matches($text,[regex]::Escape('[TEST PASS] Center zoom to original FIFO/address scheduler is correct.'))).Count -ne 3){throw 'Both SDRAM configurations must pass'}
 Write-Output "OSD VALIDATION PASS: $log (SkipLongSdram=$SkipLongSdram)"
} finally {Pop-Location}
