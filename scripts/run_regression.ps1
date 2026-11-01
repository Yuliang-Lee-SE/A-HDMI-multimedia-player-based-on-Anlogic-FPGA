<#
.SYNOPSIS
    Compile and run the current project regression set with ModelSim/Questa.

.DESCRIPTION
    The regression uses only the active TF-card WAV, frame-buffer, audio,
    picture-adjustment, transition-control and reset modules. A missing
    simulator is reported as an error; a log without an explicit success
    marker is also treated as a failure.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1
    powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 -Only s1,s4
#>
[CmdletBinding()]
param(
    [string] $ModelSimDir = '',
    [string[]] $Only = @(),
    [switch] $NoCompile
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simDir = Join-Path $repoRoot 'lab_ex5_i2s'
$compileDo = Join-Path $simDir 'compile.do'
if (-not (Test-Path -LiteralPath $compileDo)) {
    throw "Cannot find $compileDo"
}

function Find-Vsim {
    param([string] $Hint)

    $candidates = @()
    if ($Hint) { $candidates += (Join-Path $Hint 'vsim.exe') }
    $command = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $candidates += @(
        'D:\Modelsim\modelsim_ase\win32aloem\vsim.exe',
        'C:\Modelsim\modelsim_ase\win32aloem\vsim.exe',
        'D:\questa_sim\win64\vsim.exe',
        'C:\questasim64_2020.4\win64\vsim.exe',
        'C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe'
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

$vsim = Find-Vsim -Hint $ModelSimDir
if (-not $vsim) {
    Write-Error @'
ModelSim/Questa was not found. Install a version that supports SystemVerilog,
or pass the simulator bin directory:

  powershell -ExecutionPolicy Bypass -File scripts\run_regression.ps1 `
      -ModelSimDir 'D:\Modelsim\modelsim_ase\win32aloem'

Board verification remains the acceptance authority when no simulator is
available; this script never reports a silent pass.
'@
    exit 2
}

$allCases = @(
    @{ Id = 's1'; Tb = 'tb_frame_fifo'; Marker = '=== S3' },
    @{ Id = 's2'; Tb = 'tb_wav_pcm_loader'; Marker = 'PASS' },
    @{ Id = 's3'; Tb = 'tb_audio_i2s'; Marker = '=== S4 PASS' },
    @{ Id = 's4'; Tb = 'tb_audio_spectrum_overlay'; Marker = 'ALL FFT TESTS PASSED' },
    @{ Id = 's5'; Tb = 'tb_picture_adjust'; Marker = '=== PASS' },
    @{ Id = 's6'; Tb = 'tb_transition_mode_control'; Marker = 'TRANSITION_MODE_CONTROL_PASS' },
    @{ Id = 's7'; Tb = 'tb_reset_startup_guard'; Marker = 'RESET_STARTUP_GUARD_PASS' },
    @{ Id = 's8'; Tb = 'tb_board_key_debounce'; Marker = 'BOARD_KEY_DEBOUNCE_PASS' }
)

$cases = $allCases
if ($Only.Count -gt 0) {
    $wanted = @($Only | ForEach-Object { $_.ToLowerInvariant() })
    $cases = @($allCases | Where-Object { $wanted -contains $_.Id })
    if ($cases.Count -eq 0) {
        throw "No known cases in -Only: $($Only -join ',')"
    }
}

Push-Location $simDir
try {
    if (-not $NoCompile) {
        Write-Host "[compile] compile.do" -ForegroundColor Cyan
        & $vsim -c -l compile.log -do "do compile.do; quit -f" | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Compilation failed; inspect $simDir\compile.log"
        }
    }

    $failed = @()
    foreach ($case in $cases) {
        $log = Join-Path $simDir ($case.Tb + '.log')
        Write-Host "[simulate] $($case.Tb)" -ForegroundColor Cyan
        & $vsim -c -l $log "work.$($case.Tb)" -do "run -all; quit -f" | Out-Host

        $text = if (Test-Path -LiteralPath $log) {
            Get-Content -LiteralPath $log -Raw
        } else {
            ''
        }
        if ($LASTEXITCODE -ne 0) {
            $failed += "$($case.Tb): simulator exit $LASTEXITCODE"
        } elseif ($text -match '(?m)\bFAIL\b') {
            $failed += "$($case.Tb): log contains FAIL"
        } elseif ($text -notmatch [regex]::Escape($case.Marker)) {
            $failed += "$($case.Tb): missing success marker '$($case.Marker)'"
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "===== Regression failed: $($failed.Count) case(s) =====" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host "===== Regression passed: $($cases.Count) case(s) =====" -ForegroundColor Green
}
finally {
    Pop-Location
}
