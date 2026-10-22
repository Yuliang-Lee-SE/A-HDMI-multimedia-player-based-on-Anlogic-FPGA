param(
    [Parameter(Mandatory=$true)][string]$ProjectFile,
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [string]$BuildLabel = 'current-inputs-not-historical-build-proof',
    [string[]]$ArtifactPaths = @(),
    [string]$ToolExecutable
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $ProjectFile).Path
$projectDir = Split-Path -Parent $projectPath
$sourceDir = [IO.Path]::GetFullPath((Join-Path $projectDir '../user_source'))
if (Test-Path -LiteralPath $OutputFile) { throw 'Output already exists; choose a new name to preserve evidence.' }
# TD uses literal '&' in attributes such as UsedInP&R. Escape only in the
# parser's memory copy; hash and preserve the original project bytes.
$projectText = [IO.File]::ReadAllText($projectPath, [Text.Encoding]::UTF8)
[xml]$projectXml = [regex]::Replace($projectText, '&(?!#\d+;|#x[0-9a-fA-F]+;|[A-Za-z][A-Za-z0-9]*;)', '&amp;')
$entries = @()
foreach ($node in $projectXml.SelectNodes('/Project/Source_Files/*/File')) {
    $path = [IO.Path]::GetFullPath((Join-Path $projectDir ([string]$node.Path)))
    $attrs = @{}
    foreach ($attr in $node.SelectNodes('FileInfo/Attr')) { $attrs[[string]$attr.Name] = [string]$attr.Val }
    $entries += [ordered]@{ RelativePath=[string]$node.Path; Exists=(Test-Path -LiteralPath $path); Attributes=$attrs }
}
# Include generated HDL, config, constraints, initialization data and headers.
# Hash all files under the two input directories; this is a superset, not a
# claim that each file was consumed by the tool or used by a historical build.
$inputFiles = @(Get-ChildItem -LiteralPath $projectDir -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]([^\\/]*_Runs|audit_[^\\/]+)[\\/]' })
if (Test-Path -LiteralPath $sourceDir) { $inputFiles += @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File) }
$labDir = [IO.Path]::GetFullPath((Join-Path $projectDir '../..'))
# OSD resources are compiled as initialized HDL; retain the UTF-8 source,
# generator, font identity manifest and preview inputs in the same audit.
foreach ($folder in @('osd_assets','tools')) {
    $extra = Join-Path $labDir $folder
    if (Test-Path -LiteralPath $extra) {
        $inputFiles += @(Get-ChildItem -LiteralPath $extra -File | Where-Object {$_.Extension -in @('.py','.json','.png','.gif')})
    }
}
foreach ($folder in @('tf_player/rtl','tf_player/tools','fat32_offline/rtl')) {
    $extra = Join-Path $labDir $folder
    $inputFiles += @(Get-ChildItem -LiteralPath $extra -File)
}
$inputFiles += @(Get-Item -LiteralPath $PSCommandPath)
$inputFiles += @(Get-Item -LiteralPath (Join-Path $labDir 'run_verified_project_build.ps1'))
$hashes = @($inputFiles | Sort-Object FullName -Unique | ForEach-Object {
    [ordered]@{ Path=$_.FullName; Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
})
$artifacts = @($ArtifactPaths | ForEach-Object {
    $item = Get-Item -LiteralPath $_
    [ordered]@{ Path=$item.FullName; Bytes=$item.Length; SHA256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
})
$tool = $null
if ($ToolExecutable) {
    $item = Get-Item -LiteralPath $ToolExecutable
    $tool = [ordered]@{ Path=$item.FullName; Version=$item.VersionInfo.FileVersion; SHA256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
}
$result = [ordered]@{
    Label=$BuildLabel; CapturedUTC=[DateTime]::UtcNow.ToString('o'); Project=$projectPath
    Scope='Current disk snapshot; no build, download, IP generation or historical equivalence implied'
    Tool=$tool; ProjectEntries=$entries; InputHashes=$hashes; Artifacts=$artifacts
}
$destination = [IO.Path]::GetFullPath($OutputFile)
[IO.File]::WriteAllText($destination, ($result | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
Write-Output "Captured $($hashes.Count) input files and $($artifacts.Count) artifacts: $destination"
