<#
.SYNOPSIS
    角色 C 的一键回归脚本：编译并运行 S1~S7 全部 testbench。

.DESCRIPTION
    S1~S5 是官方例程的子系统用例，S6/S7 是 tb/ 下本团队新增的
    片内 ROM 语音播放器与按键/轮播/音画联动用例。

    安路 TD 的仿真流程依赖第三方仿真器（见 D:\TDengineer\doc\SWUG\SWUG107），
    本机默认没装 ModelSim，所以脚本找不到 vsim.exe 时会直接报错退出，
    不会静默跳过——跳过测试比测试失败更危险。

.PARAMETER ModelSimDir
    ModelSim 的 bin 目录，例如 D:\Modelsim\modelsim_ase\win32aloem。
    不传就在 PATH 和几个常见安装位置里找。

.PARAMETER Only
    只跑指定用例，例如 -Only s6,s7。

.PARAMETER NoCompile
    跳过编译，直接跑仿真（上一轮已经编译过、只改了激励时才用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1
    powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 -Only s6,s7
#>
[CmdletBinding()]
param(
    [string]   $ModelSimDir = '',
    [string[]] $Only        = @(),
    [switch]   $NoCompile
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simDir   = Join-Path $repoRoot 'lab_ex5_i2s'

if (-not (Test-Path -LiteralPath (Join-Path $simDir 'compile.do'))) {
    throw "找不到 $simDir\compile.do，脚本要放在仓库的 scripts\ 下运行"
}

# ---------------------------------------------------------------- 找仿真器
function Find-Vsim {
    param([string] $Hint)

    $cands = @()
    if ($Hint) { $cands += (Join-Path $Hint 'vsim.exe') }
    $cmd = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    $cands += @(
        'D:\Modelsim\modelsim_ase\win32aloem\vsim.exe',
        'C:\Modelsim\modelsim_ase\win32aloem\vsim.exe',
        'D:\questa_sim\win64\vsim.exe',
        'C:\questasim64_2020.4\win64\vsim.exe',
        'C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe'
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$vsim = Find-Vsim -Hint $ModelSimDir
if (-not $vsim) {
    Write-Host ""
    Write-Host "找不到 vsim.exe，仿真没有跑。" -ForegroundColor Red
    Write-Host "安路 TD 只能用第三方仿真器做工程仿真（参考 TD 自带文档 SWUG107）。"
    Write-Host "装好 ModelSim/Questa 后，用 -ModelSimDir 指定 bin 目录即可，例如："
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 ``"
    Write-Host "      -ModelSimDir 'D:\Modelsim\modelsim_ase\win32aloem'"
    Write-Host ""
    Write-Host "没有仿真器时，本阶段的验证证据以上板测试记录为准（见 doc\测试记录表.md）。"
    exit 2
}

Write-Host "使用仿真器：$vsim" -ForegroundColor Cyan

$allCases = @(
    @{ Id = 's1'; Tb = 'tb_bmp_read';         Name = 'S1 bmp_read 扫描/解析' },
    @{ Id = 's2'; Tb = 'tb_sd_card';          Name = 'S2 SD 卡 SPI 栈' },
    @{ Id = 's3'; Tb = 'tb_frame_fifo';       Name = 'S3 帧缓存读写' },
    @{ Id = 's4'; Tb = 'tb_audio_i2s';        Name = 'S4 I2S 音频链路' },
    @{ Id = 's5'; Tb = 'tb_video_axis';       Name = 'S5 视频时序 + AXIS' },
    @{ Id = 's6'; Tb = 'tb_audio_rom_player'; Name = 'S6 片内 ROM 语音播放器' },
    @{ Id = 's7'; Tb = 'tb_key_control';      Name = 'S7 按键/轮播/音画联动' }
)

$cases = $allCases
if ($Only.Count -gt 0) {
    $want  = $Only | ForEach-Object { $_.ToLower() }
    $cases = $allCases | Where-Object { $want -contains $_.Id }
    if ($cases.Count -eq 0) { throw "-Only 里没有可识别的用例：$($Only -join ',')" }
}

Push-Location $simDir
try {
    if (-not $NoCompile) {
        Write-Host ""
        Write-Host "[编译] compile.do" -ForegroundColor Cyan
        & $vsim -c -l compile.log -do "do compile.do; quit -f" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "编译失败，看 $simDir\compile.log" }
    }

    $failed = @()
    foreach ($c in $cases) {
        $log = "$($c.Tb).log"
        Write-Host ""
        Write-Host "[运行] $($c.Name)  (work.$($c.Tb))" -ForegroundColor Cyan
        & $vsim -c -l $log "work.$($c.Tb)" -do "run -all; quit -f" | Out-Host

        $text = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        $verdict = ($text -split "`n") | Where-Object { $_ -match '===\s*S\d' } |
                   Select-Object -Last 3
        $verdict | ForEach-Object { Write-Host "     $($_.Trim())" }

        # 判定只用 ASCII 关键字，避免 PowerShell 5.1 读非 BOM 中文文件的编码坑
        if ($LASTEXITCODE -ne 0 -or $text -match 'FAIL') {
            $failed += $c.Name
        }
        elseif ($text -match 'ALL PASS' -or $text -match 'PASS') {
            # 通过（S1~S5 没有 ASCII 通过标记，走下面的 else 兜底）
        }
        else {
            # S1~S5 只打印中文结论，这里按"没有 FAIL 就算过"处理
            if (-not ($text -match '===\s*S\d')) {
                $failed += "$($c.Name)(日志里没有结论行，按失败处理)"
            }
        }
    }

    Write-Host ""
    if ($failed.Count -eq 0) {
        Write-Host "===== 回归全部通过（$($cases.Count) 个用例）=====" -ForegroundColor Green
    } else {
        Write-Host "===== 回归失败 $($failed.Count) 个：=====" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
}
finally {
    Pop-Location
}
