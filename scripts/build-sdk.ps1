[CmdletBinding()]
param(
    [string]$BuildDirectory,
    [string]$Cmake,
    [string]$Ninja,
    [string]$RiscvPrefix = 'riscv-none-elf-',
    [switch]$Fresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
if ([string]::IsNullOrWhiteSpace($BuildDirectory)) {
    $BuildDirectory = Join-Path $projectRoot 'build\sdk'
}

function Resolve-HostTool {
    param(
        [string]$RequestedPath,
        [string]$CommandName,
        [string]$InstallHint
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "$CommandName was requested at a missing path: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Missing $CommandName. $InstallHint"
    }
    return $command.Source
}

$cmakePath = Resolve-HostTool $Cmake 'cmake' 'Install CMake 3.20 or later, or pass -Cmake <path>.'
$ninjaPath = Resolve-HostTool $Ninja 'ninja' 'Install Ninja, or pass -Ninja <path>.'
$toolchainPath = Join-Path $projectRoot 'sdk\cmake\riscv32-gcc.cmake'

if ([string]::IsNullOrWhiteSpace($RiscvPrefix)) {
    throw 'RiscvPrefix must name the GNU executable prefix, for example riscv-none-elf-.'
}
$compiler = Get-Command ($RiscvPrefix + 'gcc') -ErrorAction SilentlyContinue
$objcopy = Get-Command ($RiscvPrefix + 'objcopy') -ErrorAction SilentlyContinue
if ($null -eq $compiler -or $null -eq $objcopy) {
    throw "Could not find $($RiscvPrefix)gcc and $($RiscvPrefix)objcopy on PATH. Install a matching GNU bare-metal RISC-V toolchain or select its prefix with -RiscvPrefix."
}

if ($Fresh) {
    # CMake --fresh is supported by modern CMake and only removes generated
    # metadata inside the explicitly selected SDK build directory.
    $cmakeVersion = (& $cmakePath --version | Select-Object -First 1)
    if ($cmakeVersion -notmatch 'cmake version ([0-9]+)\.([0-9]+)') {
        throw "Unable to determine CMake version from: $cmakeVersion"
    }
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 24)) {
        throw '-Fresh requires CMake 3.24 or later; choose a new BuildDirectory instead when using an older CMake.'
    }
}

$configureArguments = @()
if ($Fresh) {
    $configureArguments += '--fresh'
}
$configureArguments += @(
    '-S', (Join-Path $projectRoot 'sdk'),
    '-B', $BuildDirectory,
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=$ninjaPath",
    "-DCMAKE_TOOLCHAIN_FILE:FILEPATH=$toolchainPath",
    "-DOMCU_RISCV_PREFIX:STRING=$RiscvPrefix"
)

& $cmakePath @configureArguments
if ($LASTEXITCODE -ne 0) {
    throw "CMake SDK configuration failed with exit code $LASTEXITCODE."
}
& $cmakePath --build $BuildDirectory --parallel
if ($LASTEXITCODE -ne 0) {
    throw "CMake SDK build failed with exit code $LASTEXITCODE."
}

Write-Output "PASS: built OpenMCU RV32IMC SDK images in $BuildDirectory"
Write-Output "Compiler: $($compiler.Source)"
Write-Output "Objcopy: $($objcopy.Source)"
