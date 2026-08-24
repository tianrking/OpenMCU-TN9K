[CmdletBinding()]
param(
    [ValidateSet('timer', 'gpio', 'uart', 'sysctrl', 'system', 'system-uart', 'tn9k')]
    [string]$Test = 'timer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$iverilogCommand = Get-Command iverilog -ErrorAction SilentlyContinue
$vvpCommand = Get-Command vvp -ErrorAction SilentlyContinue
$iverilogPath = if ($null -ne $iverilogCommand) { $iverilogCommand.Source } else { $null }
$vvpPath = if ($null -ne $vvpCommand) { $vvpCommand.Source } else { $null }

if (([string]::IsNullOrWhiteSpace($iverilogPath) -or [string]::IsNullOrWhiteSpace($vvpPath)) -and
    -not [string]::IsNullOrWhiteSpace($env:OMCU_IVERILOG_BIN)) {
    $candidateIverilog = Join-Path $env:OMCU_IVERILOG_BIN 'iverilog.exe'
    $candidateVvp = Join-Path $env:OMCU_IVERILOG_BIN 'vvp.exe'
    if ((Test-Path -LiteralPath $candidateIverilog -PathType Leaf) -and
        (Test-Path -LiteralPath $candidateVvp -PathType Leaf)) {
        $iverilogPath = $candidateIverilog
        $vvpPath = $candidateVvp
    }
}

if ([string]::IsNullOrWhiteSpace($iverilogPath) -or [string]::IsNullOrWhiteSpace($vvpPath)) {
    throw 'Icarus Verilog (iverilog and vvp) is required. Install it, add it to PATH, or set OMCU_IVERILOG_BIN to its bin directory.'
}

$buildDir = Join-Path $projectRoot 'build\rtl-smoke'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

switch ($Test) {
    'timer' {
        $output = Join-Path $buildDir 'omcu_timer_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_timer_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_timer_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'gpio' {
        $output = Join-Path $buildDir 'omcu_gpio_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_gpio_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_gpio_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'uart' {
        $output = Join-Path $buildDir 'omcu_uart_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_uart_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_uart_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'sysctrl' {
        $output = Join-Path $buildDir 'omcu_sysctrl_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_sysctrl_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_sysctrl_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'system' {
        $output = Join-Path $buildDir 'omcu_picorv32_system_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_picorv32_system_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_picorv32_system_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'system-uart' {
        $output = Join-Path $buildDir 'omcu_picorv32_uart_system_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_picorv32_uart_system_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_picorv32_uart_system_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k' {
        $output = Join-Path $buildDir 'omcu_tn9k_bringup_top_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_bringup_top_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_bringup_top_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
}
