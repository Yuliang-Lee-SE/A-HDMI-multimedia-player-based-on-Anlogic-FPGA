param([string]$Label='osd_scroll_final',[string]$Vsim='D:/j1573/modelsim/modelsim_ase/win32aloem/vsim.exe')
$ErrorActionPreference='Stop'
if($Label -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid label'}
Push-Location $PSScriptRoot
try {
 foreach($script in @('tools/prepare_osd_validation.py','tools/test_osd_resources.py','tools/prepare_osd_scroll.py')) {
  & python $script
  if($LASTEXITCODE -ne 0){throw "Preparation failed: $script"}
 }
 $log=$Label+'_scroll.log'
 if(Test-Path -LiteralPath $log){throw "Log exists: $log"}
 & $Vsim -c -do 'do run_osd_scroll.do; quit -f' -l $log
 if($LASTEXITCODE -ne 0){throw 'Scroll simulation failed'}
 $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $log))
 if($text -match '\[FAIL\]|\[TEST FAIL\]|\*\* Error:'){throw 'Scroll test failed'}
 foreach($marker in @('OSD SCROLL CONTROL COMPLETE frames=2228 errors=0','OSD SCROLL PIXELS COMPLETE checked=4300800 errors=0','OSD SCROLL REAL VIDEO COMMIT COMPLETE frames=5 commits=4 errors=0')) {
  if(!$text.Contains($marker)){throw "Missing marker: $marker"}
 }
 & ./run_osd_three_validation.ps1 -Label ($Label+'_legacy') -Vsim $Vsim -ModulesOnly
 if($LASTEXITCODE -ne 0){throw 'Existing player regression failed'}
 Write-Output 'OSD P2 VALIDATION PASS (scroll + existing player modules; storage unchanged)'
} finally {Pop-Location}
