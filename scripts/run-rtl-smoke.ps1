[CmdletBinding()]
param(
    [ValidateSet('timer', 'timer1', 'timer1-fabric', 'alarm', 'pulse', 'alarm-pulse-fabric', 'fault', 'fault-fabric', 'gpio', 'uart', 'uart1', 'spi', 'i2c', 'wdt', 'wdt-supervisor', 'pwm', 'pwm1', 'pwm1-fabric', 'irqctrl', 'sysctrl', 'pinmux', 'user-flash', 'pcpi-div', 'system', 'system-uart', 'sdk-isa', 'sdk-peripherals', 'sdk-i2c', 'sdk-irq', 'tn9k-wdt', 'tn9k-peripherals', 'tn9k-pwm1', 'tn9k-timer1', 'tn9k-boot-request', 'tn9k', 'mcu-top')]
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
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
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
    'spi' {
        $output = Join-Path $buildDir 'omcu_spi_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_spi_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_spi_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'i2c' {
        $output = Join-Path $buildDir 'omcu_i2c_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_i2c_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_i2c_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'wdt' {
        $output = Join-Path $buildDir 'omcu_wdt_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_wdt_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_wdt_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pwm' {
        $output = Join-Path $buildDir 'omcu_pwm_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pwm_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pwm_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'irqctrl' {
        $output = Join-Path $buildDir 'omcu_irq_ctrl_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_irq_ctrl_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_irq_ctrl_tb -o $output @sources
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
    'wdt-supervisor' {
        $output = Join-Path $buildDir 'omcu_wdt_supervisor_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_wdt_supervisor_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_wdt_supervisor_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'timer1' {
        $output = Join-Path $buildDir 'omcu_timer1_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_timer1_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_timer1_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'alarm' {
        $output = Join-Path $buildDir 'omcu_alarm_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_alarm_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_alarm_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pulse' {
        $output = Join-Path $buildDir 'omcu_pulse_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pulse_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pulse_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'fault' {
        $output = Join-Path $buildDir 'omcu_fault_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_fault_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_fault_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'alarm-pulse-fabric' {
        $output = Join-Path $buildDir 'omcu_alarm_pulse_fabric_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_alarm_pulse_fabric_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_alarm_pulse_fabric_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'fault-fabric' {
        $output = Join-Path $buildDir 'omcu_fault_fabric_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_fault_fabric_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_fault_fabric_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'timer1-fabric' {
        $output = Join-Path $buildDir 'omcu_timer1_fabric_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_timer1_fabric_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_timer1_fabric_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pwm1' {
        $output = Join-Path $buildDir 'omcu_pwm1_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pwm1_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pwm1_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pwm1-fabric' {
        $output = Join-Path $buildDir 'omcu_pwm1_fabric_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pwm1_fabric_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pwm1_fabric_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'uart1' {
        $output = Join-Path $buildDir 'omcu_uart1_fabric_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_uart1_fabric_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_uart1_fabric_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pinmux' {
        $output = Join-Path $buildDir 'omcu_pinmux_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pinmux_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pinmux_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'user-flash' {
        $output = Join-Path $buildDir 'omcu_user_flash_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_user_flash_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_user_flash_tb -o $output @sources
        if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
        & $vvpPath $output
        if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
    }
    'pcpi-div' {
        $output = Join-Path $buildDir 'omcu_pcpi_divider_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\cpu\omcu_pcpi_divider.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_pcpi_divider_tb.sv')
        )
        & $iverilogPath -g2012 -s omcu_pcpi_divider_tb -o $output @sources
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
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
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
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
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
    'sdk-isa' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_isa_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for sdk-isa: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_rv32im_sdk_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_rv32im_sdk_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_rv32im_sdk_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'sdk-peripherals' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_peripheral_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for sdk-peripherals: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_peripheral_sdk_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_peripheral_sdk_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_peripheral_sdk_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'sdk-i2c' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_i2c_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for sdk-i2c: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_i2c_sdk_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_i2c_sdk_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_i2c_sdk_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'sdk-irq' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_irq_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for sdk-irq: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_irq_sdk_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_irq_sdk_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_irq_sdk_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k-wdt' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_wdt_reset_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for tn9k-wdt: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_tn9k_wdt_reset_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_wdt_reset_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_wdt_reset_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k-peripherals' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_peripheral_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for tn9k-peripherals: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_tn9k_peripheral_io_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_peripheral_io_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_peripheral_io_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k-pwm1' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_pwm1_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for tn9k-pwm1: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_tn9k_pwm1_io_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_pwm1_io_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_pwm1_io_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k-timer1' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_timer1_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for tn9k-timer1: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_tn9k_timer1_io_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_timer1_io_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_timer1_io_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'tn9k-boot-request' {
        $firmware = Join-Path $projectRoot 'build\sdk\omcu_boot_request_smoke.hex'
        if (-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
            throw "Compiled SDK image is required for tn9k-boot-request: $firmware. Build it with cmake -S sdk -B build/sdk first."
        }
        $output = Join-Path $buildDir 'omcu_tn9k_boot_request_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_boot_request_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_boot_request_tb -o $output @sources
            if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }
            & $vvpPath $output
            if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
        } finally {
            Pop-Location
        }
    }
    'mcu-top' {
        $output = Join-Path $buildDir 'omcu_tn9k_mcu_top_tb.vvp'
        $sources = @(
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_pkg.sv'),
            (Join-Path $projectRoot 'third_party\picorv32\picorv32.v'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_gpio.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_uart.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
            (Join-Path $projectRoot 'rtl\bus\omcu_mmio_fabric.sv'),
            (Join-Path $projectRoot 'rtl\cpu\omcu_picorv32_system.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_bringup_top.sv'),
            (Join-Path $projectRoot 'rtl\platform\tangnano9k\omcu_tn9k_mcu_top.sv'),
            (Join-Path $projectRoot 'tests\rtl\gowin_flash608k_stub.sv'),
            (Join-Path $projectRoot 'tests\rtl\omcu_tn9k_mcu_top_tb.sv')
        )
        Push-Location $projectRoot
        try {
            & $iverilogPath -g2012 -s omcu_tn9k_mcu_top_tb -o $output @sources
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
            (Join-Path $projectRoot 'rtl\peripherals\omcu_timer1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_alarm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pulse.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_fault.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_spi.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_i2c.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_wdt.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pwm1.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_irq_ctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_sysctrl.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_pinmux.sv'),
            (Join-Path $projectRoot 'rtl\peripherals\omcu_user_flash.sv'),
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
