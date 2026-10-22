param(
    [Parameter(Mandatory=$true)][string]$RunName,
    [Parameter(Mandatory=$true)][string]$ReviewFile,
    [string]$TdExecutable='D:/FPGA-learning/Anlogic/TD5.6.2/bin/td_commands_prompt.exe'
)
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[A-Za-z0-9_-]+$') {throw 'Invalid run name'}
$labRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runRoot=Join-Path $labRoot ('src/td_project/'+$RunName+'_Runs')
$phyRoot=Join-Path $runRoot 'phy_1'
if(!(Test-Path -LiteralPath (Join-Path $phyRoot '.opt_route.end.f'))) {throw 'Routing is incomplete'}
if(Test-Path -LiteralPath (Join-Path $phyRoot '.bitgen.begin.f')) {throw 'Bitgen already attempted; preserve this run'}
$review=Get-Content -LiteralPath $ReviewFile -Raw -Encoding UTF8 | ConvertFrom-Json
if($review.Run -ne $RunName -or $review.DefaultFiles -ne 32) {throw 'Review run/configuration mismatch'}
foreach($field in @('RequiredRegressionsPassed','ConstraintsAndCDCReviewed','RAMAndROMReviewed','CriticalWarningsReviewed')) {
    if($review.$field -ne $true) {throw "Missing acceptance: $field"}
}
if(!$review.Evidence -or !$review.Reports) {throw 'Review must identify regression evidence and reports'}
foreach($item in @($review.Evidence)+@($review.Reports)) {
    if((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.SHA256) {throw "Review evidence changed: $($item.Path)"}
}
$beforePath=Join-Path $runRoot 'inputs_before.json'
if((Get-FileHash -LiteralPath $beforePath -Algorithm SHA256).Hash -ne $review.InputSnapshotSHA256) {throw 'Review input snapshot changed'}
$before=Get-Content -LiteralPath $beforePath -Raw -Encoding UTF8 | ConvertFrom-Json
if((Get-FileHash -LiteralPath $TdExecutable -Algorithm SHA256).Hash -ne $before.Tool.SHA256) {throw 'TD executable changed'}
$templateFiles=@(Get-ChildItem -LiteralPath (Join-Path $labRoot 'build_flow_templates') -Recurse -File | ForEach-Object {$_.FullName})
$currentPath=Join-Path $runRoot 'inputs_before_bit.json'
& (Join-Path $labRoot 'capture_build_inputs.ps1') -ProjectFile (Join-Path $labRoot 'src/td_project/HDMI1.4b_Transmitter_v1.0.al') -OutputFile $currentPath -BuildLabel ($RunName+'-reviewed-bit') -ToolExecutable $TdExecutable -ArtifactPaths $templateFiles
$current=Get-Content -LiteralPath $currentPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Assert-SameInputs($left,$right) {
    foreach($group in @('InputHashes','Artifacts')) {
        if(Compare-Object @($left.$group | ForEach-Object {$_.Path+' '+$_.SHA256}) @($right.$group | ForEach-Object {$_.Path+' '+$_.SHA256})) {throw "Build inputs changed: $group"}
    }
}
Assert-SameInputs $before $current
$timingPath=Join-Path $phyRoot 'HDMI1.4b_Transmitter_v1.0_pr.timing'
$timing=[IO.File]::ReadAllText($timingPath)
$setup=[regex]::Match($timing,'SWNS:\s*(-?[\d.]+)ns, STNS:\s*(-?[\d.]+)ns')
$hold=[regex]::Match($timing,'HWNS:\s*(-?[\d.]+)ns, HTNS:\s*(-?[\d.]+)ns')
if(!$setup.Success -or !$hold.Success -or $timing -notmatch 'Confidence\s*:\s*Routed') {throw 'Missing routed timing'}
$values=@($setup.Groups[1].Value,$setup.Groups[2].Value,$hold.Groups[1].Value,$hold.Groups[2].Value) | ForEach-Object {[double]::Parse($_,[Globalization.CultureInfo]::InvariantCulture)}
if(@($values | Where-Object {$_ -lt 0}).Count) {throw 'Timing violation; bitgen forbidden'}
$cfgPath=Join-Path $phyRoot 'settings.cfg'
$cfg=[IO.File]::ReadAllText($cfgPath,[Text.Encoding]::UTF8)
if($cfg -notmatch 'set start_step opt_place' -or $cfg -notmatch 'set end_step opt_route') {throw 'Unexpected routed flow settings'}
$cfg=$cfg.Replace('set start_step opt_place','set start_step bitgen').Replace('set end_step opt_route','set end_step bitgen')
[IO.File]::WriteAllText($cfgPath,$cfg,(New-Object Text.UTF8Encoding($false)))
$cfgHash=(Get-FileHash -LiteralPath $cfgPath -Algorithm SHA256).Hash
Push-Location $phyRoot
try { & $TdExecutable 'HDMI1.4b_Transmitter_v1.0.tcl' *> 'driver_bitgen.log';$tdExit=$LASTEXITCODE } finally {Pop-Location}
$log=[IO.File]::ReadAllText((Join-Path $phyRoot 'driver_bitgen.log'))
if($tdExit -ne 0 -or $log -match '\bERROR\b' -or !(Test-Path -LiteralPath (Join-Path $phyRoot '.bitgen.end.f'))) {throw 'Bitgen failed; candidate rejected'}
$afterPath=Join-Path $runRoot 'inputs_after_bit.json'
& (Join-Path $labRoot 'capture_build_inputs.ps1') -ProjectFile (Join-Path $labRoot 'src/td_project/HDMI1.4b_Transmitter_v1.0.al') -OutputFile $afterPath -BuildLabel ($RunName+'-after-bit') -ToolExecutable $TdExecutable -ArtifactPaths $templateFiles
$after=Get-Content -LiteralPath $afterPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-SameInputs $before $after
$bit=Join-Path $phyRoot 'HDMI1.4b_Transmitter_v1.0.bit'
$result=[ordered]@{Run=$RunName;DefaultFiles=32;Bit=$bit;SHA256=(Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash;SetupWNS=$values[0];SetupTNS=$values[1];HoldWNS=$values[2];HoldTNS=$values[3];ReviewSHA256=(Get-FileHash -LiteralPath $ReviewFile -Algorithm SHA256).Hash;BitgenSettingsSHA256=$cfgHash;Status='Local candidate; board/Flash/power-cycle unverified'}
[IO.File]::WriteAllText((Join-Path $runRoot 'build_result.json'),($result|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json
