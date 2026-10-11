param([string]$Label='osd_three',[string]$Vsim='D:/j1573/modelsim/modelsim_ase/win32aloem/vsim.exe',[switch]$ModulesOnly)
$ErrorActionPreference='Stop'
if($Label -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid label'}
Push-Location $PSScriptRoot
try {
 & python tools/prepare_osd_validation.py
 if($LASTEXITCODE -ne 0){throw 'Golden preparation failed'}
 & python tools/test_osd_resources.py
 if($LASTEXITCODE -ne 0){throw 'Resource checks failed'}
 $jobs=@(
  @{Name='modules';Commands='do run_osd_validation.do; do run_osd_video_commit.do; do run_half_canvas.do; do run_board_zoom_control_tests.do; set display_commit 1; do run_board_zoom_control_tests.do; do run_half_bmp_control.do; set bmp_display_commit 1; do run_half_bmp_control.do; do run_bmp_prime.do; do run_board_zoom_tests.do; do run_board_zoom_fifo_tests.do; quit -f';Count=5},
  @{Name='storage';Commands='set display_commit 1; set diag_height 480; set diag_library osd_three_storage; do run_zoom_real_sdram.do; set diag_height 48; set forced_refresh 1; do run_zoom_real_sdram.do; quit -f';Count=2}
 )
 if($ModulesOnly){$jobs=@($jobs | Where-Object {$_.Name -eq 'modules'})}
 foreach($job in $jobs){
  $log=$Label+'_'+$job.Name+'.log'
  if(Test-Path -LiteralPath $log){throw "Log exists: $log"}
  & $Vsim -c -do $job.Commands -l $log
  if($LASTEXITCODE -ne 0){throw "Simulation failed: $log"}
  $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $log))
  if($text -match '\[FAIL\]|\[TEST FAIL\]|\*\* Error:'){throw "Failed simulation: $log"}
  if($job.Name -eq 'modules'){
   foreach($marker in @('OSD PIXELS COMPLETE checked=2150400 errors=0','OSD ROM COMPLETE errors=0','OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0','REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0')){if(!$text.Contains($marker)){throw "Missing marker: $marker"}}
   if(([regex]::Matches($text,'Board zoom controller integration is correct')).Count -ne 4){throw 'Both real/synthetic BMP controller configurations must pass'}
  } else {if(([regex]::Matches($text,'Center zoom to original FIFO/address scheduler is correct')).Count -ne 2){throw 'Both storage configurations must pass'}}
 }
 Write-Output "OSD THREE-MODE VALIDATION PASS (ModulesOnly=$ModulesOnly)"
} finally {Pop-Location}
