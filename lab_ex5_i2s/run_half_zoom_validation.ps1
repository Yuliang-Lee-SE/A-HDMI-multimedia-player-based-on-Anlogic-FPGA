param([string]$Label='half_validation',[string]$VsimExecutable='D:/j1573/modelsim/modelsim_ase/win32aloem/vsim.exe')
$ErrorActionPreference='Stop'
if($Label -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid label'}
$jobs=@(
 @{Name='modules';Commands='do run_half_canvas.do; do run_board_zoom_control_tests.do; do run_half_bmp_control.do; do run_bmp_prime.do; do run_board_zoom_tests.do; do run_board_zoom_fifo_tests.do; quit -f'},
 @{Name='sdram_full';Commands='set diag_height 480; set diag_library half_sdram_full; do run_zoom_real_sdram.do; quit -f'},
 @{Name='sdram_refresh';Commands='set diag_height 48; set forced_refresh 1; set diag_library half_sdram_refresh; do run_zoom_real_sdram.do; quit -f'}
)
Push-Location $PSScriptRoot
try {
 foreach($job in $jobs){
  $log=Join-Path $PSScriptRoot ($Label+'_'+$job.Name+'.log')
  if(Test-Path -LiteralPath $log){throw "Log exists; choose a new label: $log"}
  & $VsimExecutable -c -l $log -do $job.Commands
  if($LASTEXITCODE -ne 0){throw "Simulation failed: $log"}
  $text=[IO.File]::ReadAllText($log)
  if($text -match '\[FAIL\]|\[TEST FAIL\]' -or $text -notmatch 'TEST PASS'){throw "Invalid completion: $log"}
 }
} finally {Pop-Location}
Write-Output 'Three-mode local validation passed; hardware remains unverified.'
