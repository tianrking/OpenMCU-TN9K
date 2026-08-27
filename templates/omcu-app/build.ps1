[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
$sdkDir = $env:OMCU_SDK_PATH
$riscvPrefix = if ($env:OMCU_RISCV_PREFIX) {
    $env:OMCU_RISCV_PREFIX
} else {
    'riscv-none-elf-'
}
$cmake = if ($env:OMCU_CMAKE) { $env:OMCU_CMAKE } else { 'cmake' }
$ninja = if ($env:OMCU_NINJA) { $env:OMCU_NINJA } else { 'ninja' }
$python = if ($env:OMCU_PYTHON) { $env:OMCU_PYTHON } else { 'python' }

if ([string]::IsNullOrWhiteSpace($sdkDir)) {
    throw 'Set OMCU_SDK_PATH to <OpenMCU-TN9K>\sdk.'
}

& $cmake -S $appDir -B (Join-Path $appDir 'build') -G Ninja `
    "-DCMAKE_MAKE_PROGRAM:FILEPATH=$ninja" `
    "-DOMCU_SDK_PATH:PATH=$sdkDir" `
    "-DOMCU_RISCV_PREFIX:STRING=$riscvPrefix"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }

& $cmake --build (Join-Path $appDir 'build') --target my_omcu_app --parallel
if ($LASTEXITCODE -ne 0) { throw "Build failed: $LASTEXITCODE" }

$image = Join-Path $appDir 'build\my_omcu_app.omcu'
& $python (Join-Path $sdkDir '..\tools\omcu_image.py') validate --image $image
if ($LASTEXITCODE -ne 0) { throw "Image validation failed: $LASTEXITCODE" }
Write-Output "PASS: $image"
