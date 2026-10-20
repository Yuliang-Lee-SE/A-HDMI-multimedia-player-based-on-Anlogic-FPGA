param([string]$Label='osd_layers_final',[string]$Vsim='D:/j1573/modelsim/modelsim_ase/win32aloem/vsim.exe')
$ErrorActionPreference='Stop'
if($Label -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid label'}
Push-Location $PSScriptRoot
try {
 foreach($script in @('tools/prepare_osd_validation.py','tools/test_osd_resources.py','tools/prepare_osd_scroll.py','tools/prepare_osd_layers.py')) {
  & python $script
  if($LASTEXITCODE -ne 0){throw "Preparation failed: $script"}
 }
 $log=$Label+'_layers.log'
 if(Test-Path -LiteralPath $log){throw "Log exists: $log"}
 & $Vsim -c -do 'do run_osd_layers.do; do run_osd_scroll.do; quit -f' -l $log
 if($LASTEXITCODE -ne 0){throw 'P3/P2 simulation failed'}
 $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $log))
 if($text -match '\[FAIL\]|\[TEST FAIL\]|\*\* Error:'){throw 'P3/P2 test failed'}
 foreach($marker in @('OSD P3 CONFIG COMPLETE errors=0','OSD P3 SCROLL CONTROL COMPLETE frames=2243 errors=0',
  'OSD P3 PIXELS COMPLETE checked=2764800 errors=0','OSD P3 PIPELINE COMPLETE checked=569408',
  'OSD P3 REAL VIDEO COMMIT COMPLETE frames=5 commits=4 errors=0',
  'OSD SCROLL CONTROL COMPLETE frames=2228 errors=0','OSD SCROLL PIXELS COMPLETE checked=4300800 errors=0',
  'OSD SCROLL REAL VIDEO COMMIT COMPLETE frames=5 commits=4 errors=0')) {
  if(!$text.Contains($marker)){throw "Missing marker: $marker"}
 }
 & ./run_osd_three_validation.ps1 -Label ($Label+'_legacy') -Vsim $Vsim -ModulesOnly
 if($LASTEXITCODE -ne 0){throw 'Existing player regression failed'}
 Write-Output 'OSD P3 VALIDATION PASS (layers + P2 + existing player modules; storage unchanged)'
} finally {Pop-Location}
