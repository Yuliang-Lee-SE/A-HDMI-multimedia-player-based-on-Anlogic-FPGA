param(
    [Parameter(Mandatory=$true)][string]$RunName,
    [string]$TdExecutable = 'D:/FPGA-learning/Anlogic/TD5.6.2/bin/td_commands_prompt.exe',
    [switch]$ValidateOnly,
    [switch]$RouteOnly
)
$ErrorActionPreference = 'Stop'
if ($RunName -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use letters, digits, underscore or hyphen for RunName.' }
$labRoot = $PSScriptRoot
$templateRoot = Join-Path $labRoot 'build_flow_templates'
$projectFile = Join-Path $labRoot 'src/td_project/HDMI1.4b_Transmitter_v1.0.al'
$runRoot = Join-Path $labRoot ('src/td_project/'+$RunName+'_Runs')
if (Test-Path -LiteralPath $runRoot) { throw 'Run directory exists; choose a new name. Previous evidence is preserved.' }
if (!(Test-Path -LiteralPath $TdExecutable)) { throw 'TD executable does not exist.' }
# The captured .prj is specific to this project's source list. Reject later
# additions/config changes rather than silently building a stale snapshot.
function Get-ProjectSignature([string]$File,[string]$BaseDirectory) {
    $text=[IO.File]::ReadAllText($File,[Text.Encoding]::UTF8)
    [xml]$xml=[regex]::Replace($text,'&(?!#\d+;|#x[0-9a-fA-F]+;|[A-Za-z][A-Za-z0-9]*;)','&amp;')
    'TOP='+[string]$xml.Project.TOP_MODULE.MODULE
    'DEVICE='+[string]$xml.Project.HardWare.Device
    foreach($node in $xml.SelectNodes('/Project/Source_Files/*/File')) {
        $full=[IO.Path]::GetFullPath((Join-Path $BaseDirectory ([string]$node.Path))).ToLowerInvariant()
        $attributes=@(foreach($attr in $node.SelectNodes('FileInfo/Attr')) { [string]$attr.Name+'='+[string]$attr.Val }) | Sort-Object
        $full+'|'+($attributes -join ';')
    }
}
$actualSignature=@(Get-ProjectSignature $projectFile (Split-Path -Parent $projectFile))
foreach($templateStage in @('syn_1','phy_1')) {
    $templateSignature=@(Get-ProjectSignature (Join-Path $templateRoot ($templateStage+'/HDMI1.4b_Transmitter_v1.0.prj')) (Join-Path $runRoot $templateStage))
    if ($actualSignature.Count -ne $templateSignature.Count -or
        [string]::Join("`n",$actualSignature) -cne [string]::Join("`n",$templateSignature)) {
        throw "Project source order/list/attributes differ from $templateStage template; regenerate and review the project flow templates."
    }
}
if ($ValidateOnly) { Write-Output 'Template source list, attributes, top and device match the current project. No build started.'; return }
foreach ($stage in @('syn_1','phy_1')) {
    $destination = Join-Path $runRoot $stage
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($name in @('HDMI1.4b_Transmitter_v1.0.prj','HDMI1.4b_Transmitter_v1.0.tcl','settings.cfg')) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $templateRoot $stage) $name) -Destination (Join-Path $destination $name)
    }
}
# Use the captured C flow and its IP constraints. Stop at routing initially;
# bit generation is a separate step after timing and error checks.
$phyCfg = Join-Path $runRoot 'phy_1/settings.cfg'
$cfgText = [IO.File]::ReadAllText($phyCfg,[Text.Encoding]::UTF8).Replace('set end_step bitgen','set end_step opt_route')
[IO.File]::WriteAllText($phyCfg,$cfgText,(New-Object Text.UTF8Encoding($false)))
$templateFiles = @(Get-ChildItem -LiteralPath $templateRoot -Recurse -File | ForEach-Object {$_.FullName})
& (Join-Path $labRoot 'capture_build_inputs.ps1') -ProjectFile $projectFile -OutputFile (Join-Path $runRoot 'inputs_before.json') -BuildLabel $RunName -ToolExecutable $TdExecutable -ArtifactPaths $templateFiles
function Invoke-CheckedStage([string]$Stage,[string]$Marker,[string]$OutputName) {
    $stageDir = Join-Path $runRoot $Stage
    Push-Location $stageDir
    try {
        & $TdExecutable 'HDMI1.4b_Transmitter_v1.0.tcl' *> $OutputName
        $tdExit = $LASTEXITCODE
    } finally { Pop-Location }
    $outputPath = Join-Path $stageDir $OutputName
    $outputText = [IO.File]::ReadAllText($outputPath)
    if ($tdExit -ne 0 -or $outputText -match '\bERROR\b' -or !(Test-Path -LiteralPath (Join-Path $stageDir $Marker))) {
        throw "TD stage failed: $Stage; inspect $outputPath"
    }
}
Invoke-CheckedStage 'syn_1' '.opt_gate.end.f' 'driver_syn.log'
Invoke-CheckedStage 'phy_1' '.opt_route.end.f' 'driver_phy.log'
$timingPath = Join-Path $runRoot 'phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing'
$timing = [IO.File]::ReadAllText($timingPath)
$setupMatch = [regex]::Match($timing,'SWNS:\s*(-?[\d.]+)ns, STNS:\s*(-?[\d.]+)ns')
$holdMatch = [regex]::Match($timing,'HWNS:\s*(-?[\d.]+)ns, HTNS:\s*(-?[\d.]+)ns')
if (!$setupMatch.Success -or !$holdMatch.Success -or $timing -notmatch 'Confidence\s*:\s*Routed') { throw 'Missing final routed timing status.' }
$inv = [Globalization.CultureInfo]::InvariantCulture
$values = @($setupMatch.Groups[1].Value,$setupMatch.Groups[2].Value,$holdMatch.Groups[1].Value,$holdMatch.Groups[2].Value) | ForEach-Object {[double]::Parse($_,$inv)}
& (Join-Path $labRoot 'capture_build_inputs.ps1') -ProjectFile $projectFile -OutputFile (Join-Path $runRoot 'inputs_after.json') -BuildLabel $RunName -ToolExecutable $TdExecutable -ArtifactPaths $templateFiles
$before = Get-Content (Join-Path $runRoot 'inputs_before.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$after = Get-Content (Join-Path $runRoot 'inputs_after.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (Compare-Object @($before.InputHashes | ForEach-Object {$_.Path+' '+$_.SHA256}) @($after.InputHashes | ForEach-Object {$_.Path+' '+$_.SHA256})) { throw 'Inputs changed during build; candidate rejected.' }
if (@($values | Where-Object {$_ -lt 0}).Count -gt 0) { throw "Timing violation; bit not generated. See $timingPath" }
if ($RouteOnly) {
    $routeSummary = [ordered]@{Run=$RunName;SetupWNS=$values[0];SetupTNS=$values[1];HoldWNS=$values[2];HoldTNS=$values[3];Status='Routed only; bit generation withheld pending regression, constraints and RAM/ROM review'}
    [IO.File]::WriteAllText((Join-Path $runRoot 'route_result.json'),($routeSummary|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $routeSummary | ConvertTo-Json
    return
}
$cfgText=$cfgText.Replace('set start_step opt_place','set start_step bitgen').Replace('set end_step opt_route','set end_step bitgen')
[IO.File]::WriteAllText($phyCfg,$cfgText,(New-Object Text.UTF8Encoding($false)))
Invoke-CheckedStage 'phy_1' '.bitgen.end.f' 'driver_bitgen.log'
$bitPath = Join-Path $runRoot 'phy_1/HDMI1.4b_Transmitter_v1.0.bit'
$summary = [ordered]@{Run=$RunName;Bit=$bitPath;SHA256=(Get-FileHash -LiteralPath $bitPath -Algorithm SHA256).Hash;SetupWNS=$values[0];SetupTNS=$values[1];HoldWNS=$values[2];HoldTNS=$values[3];Status='Local candidate only; inspect warnings/coverage; board unverified'}
[IO.File]::WriteAllText((Join-Path $runRoot 'build_result.json'),($summary|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$summary | ConvertTo-Json
