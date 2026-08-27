[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [switch]$NoBoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sdkDir = $env:OMCU_SDK_PATH
$python = if ($env:OMCU_PYTHON) { $env:OMCU_PYTHON } else { 'python' }
$image = Join-Path $PSScriptRoot 'build\my_omcu_app.omcu'

if ([string]::IsNullOrWhiteSpace($sdkDir)) {
    throw 'Set OMCU_SDK_PATH to <OpenMCU-TN9K>\sdk.'
}
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
    throw 'Missing build\my_omcu_app.omcu; run .\build.ps1 first.'
}

$arguments = @(
    (Join-Path $sdkDir '..\tools\omcu_flash.py'),
    '--port', $Port,
    '--image', $image
)
if ($NoBoot) { $arguments += '--no-boot' }

& $python @arguments
if ($LASTEXITCODE -ne 0) { throw "Application flash failed: $LASTEXITCODE" }
